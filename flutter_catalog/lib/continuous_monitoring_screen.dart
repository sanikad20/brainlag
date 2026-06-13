import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'usage_service.dart';

class ContinuousMonitoringScreen extends StatefulWidget {
  const ContinuousMonitoringScreen({super.key});

  @override
  State<ContinuousMonitoringScreen> createState() =>
      _ContinuousMonitoringScreenState();
}

class _ContinuousMonitoringScreenState
    extends State<ContinuousMonitoringScreen> {

  bool   _isFetching    = false;
  bool   _hasPermission = false;
  String _statusMsg     = 'Checking permissions…';

  List<DayUsageRaw>  _history    = [];
  PersonalBaseline?  _baseline;
  double?            _todayScreenTime;  // live screen time
  int                _daysSinceInstall = 0;

  final Map<int, double> _scores = {};
  final Map<int, String> _levels = {};

  Timer? _autoTimer;
  Timer? _screenTimeTimer;  // refreshes live screen time every 5 min

  @override
  void initState() {
    super.initState();
    _checkPermissionAndLoad();
    // Refresh every 30 min
    _autoTimer = Timer.periodic(
        const Duration(minutes: 30), (_) => _checkPermissionAndLoad());
    // Update live screen time every 5 min
    _screenTimeTimer = Timer.periodic(
        const Duration(minutes: 5), (_) => _refreshTodayScreenTime());
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _screenTimeTimer?.cancel();
    super.dispose();
  }

  // ── Permission ────────────────────────────────────────────────────────────

  Future<void> _checkPermissionAndLoad() async {
    final granted = await UsageService.instance.hasPermission();
    setState(() => _hasPermission = granted);
    if (granted) {
      await _loadAndPredict();
    } else {
      setState(() => _statusMsg = 'Grant usage access to continue.');
    }
  }

  // ── Live screen time refresh ──────────────────────────────────────────────

  Future<void> _refreshTodayScreenTime() async {
    if (!_hasPermission) return;
    final h = await UsageService.instance.fetchTodayScreenTime();
    if (mounted) setState(() => _todayScreenTime = h);
  }

  // ── Main load ─────────────────────────────────────────────────────────────

  Future<void> _loadAndPredict() async {
    if (_isFetching) return;
    setState(() {
      _isFetching = true;
      _statusMsg  = 'Reading your Digital Wellbeing data…';
    });

    try {
      // 1. Get install date
      await UsageService.instance.getInstallDate();
      final daysSince = UsageService.instance.daysSinceInstall;

      // 2. Fetch real history from Android — only since install date
      final history = await UsageService.instance.fetchHistory(
          maxDays: 14, forceRefresh: true);

      // 3. Fetch live screen time for today
      final todayScreen =
          await UsageService.instance.fetchTodayScreenTime();

      if (history.isEmpty) {
        setState(() {
          _statusMsg   = 'No usage data yet. Use your phone normally '
              'and check back tomorrow.';
          _isFetching  = false;
          _daysSinceInstall = daysSince;
        });
        return;
      }

      final baseline = UsageService.instance.baseline!;

      setState(() {
        _history          = history;
        _baseline         = baseline;
        _todayScreenTime  = todayScreen;
        _daysSinceInstall = daysSince;
        _statusMsg        = 'Analysing ${history.length}-day pattern…';
      });

      // 4. Run burnout prediction for each consecutive day pair
      _scores.clear();
      _levels.clear();

      for (int i = 0; i < history.length - 1; i++) {
        final newer = history[i];
        final older = history[i + 1];
        try {
          final result = await ApiService.instance.predictTwoDay(
            day1: _toApiUsage(older, baseline),
            day2: _toApiUsage(newer, baseline),
          );
          if (mounted) {
            setState(() {
              _scores[i] = result.score;
              _levels[i] = result.level;
            });
          }
        } catch (_) {}
      }

      setState(() {
        _statusMsg = 'Updated ${_fmt(DateTime.now())}  '
            '· ${history.length} days of data';
      });

    } catch (e) {
      setState(() => _statusMsg = 'Error: $e');
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  DayUsage _toApiUsage(DayUsageRaw raw, PersonalBaseline b) => DayUsage(
        screenTimeHours:    raw.screenTimeHours,
        appSwitchesPerHour: raw.appSwitchesPerHour,
        uniqueAppsPerDay:   raw.uniqueAppsPerDay.toDouble(),
        socialAppRatio:     raw.socialAppRatio,
        workAppRatio:       raw.workAppRatio,
        entertainmentRatio: raw.entertainmentRatio,
        wellnessRatio:      raw.wellnessRatio,
        sleepHours:         7.0,
        sleepQuality:       3.0,
        exerciseMinPerWeek: 120.0,
        socialHoursPerWeek: 10.0,
        callCount:          5.0,
        missedCallRatio:    0.1,
        smsCount:           20.0,
      );

  String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  // ── Deviation alerts using dynamic thresholds ─────────────────────────────

  List<String> get _deviationAlerts {
    if (_history.isEmpty || _baseline == null) return [];
    final today   = _history.first;
    final b       = _baseline!;
    final alerts  = <String>[];

    // Use DYNAMIC thresholds from PersonalBaseline
    if (today.screenTimeHours > b.thresholdScreenTime)
      alerts.add('📱 Screen time ${today.screenTimeHours.toStringAsFixed(1)}h '
          '> your threshold ${b.thresholdScreenTime.toStringAsFixed(1)}h');

    if (today.socialAppRatio > b.thresholdSocialRatio)
      alerts.add('📲 Social apps ${(today.socialAppRatio * 100).toStringAsFixed(0)}% '
          '> your threshold ${(b.thresholdSocialRatio * 100).toStringAsFixed(0)}%');

    if (today.appSwitchesPerHour > b.thresholdAppSwitches)
      alerts.add('🔀 App switches ${today.appSwitchesPerHour.toStringAsFixed(0)}/hr '
          '> your threshold ${b.thresholdAppSwitches.toStringAsFixed(0)}/hr');

    if (b.screenZScore(today.screenTimeHours) > 1.5)
      alerts.add('⚠️ Screen time is '
          '${b.screenZScore(today.screenTimeHours).toStringAsFixed(1)}σ '
          'above your personal average');

    if (b.socialZScore(today.socialAppRatio) > 1.5)
      alerts.add('⚠️ Social usage is '
          '${b.socialZScore(today.socialAppRatio).toStringAsFixed(1)}σ '
          'above your normal');

    if (today.workAppRatio < b.avgWorkRatio * 0.6 && b.avgWorkRatio > 0.1)
      alerts.add('💼 Work app usage dropped significantly today');

    return alerts;
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Color _levelColor(String level) {
    if (level.contains('Low'))      return Colors.green;
    if (level.contains('Moderate')) return Colors.orange;
    if (level.contains('High'))     return Colors.red;
    return Colors.white;
  }

  Widget _infoCard({
    required String title,
    required String value,
    required IconData icon,
    Color? valueColor,
    String? subtitle,
    Color? borderColor,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF232325),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor ?? Colors.white12),
        ),
        child: Row(children: [
          Icon(icon, color: const Color(0xFF8A5CE6), size: 22),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
              if (subtitle != null)
                Text(subtitle,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
            ],
          )),
          Text(value, style: TextStyle(
              color: valueColor ?? Colors.white,
              fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
      );

  // Today's LIVE screen time card — highlighted
  Widget _liveScreenTimeCard() {
    final live    = _todayScreenTime;
    final history = _history.isNotEmpty ? _history.first : null;
    final b       = _baseline;

    // Use live value if available, else fall back to history
    final displayHours = live ?? history?.screenTimeHours;
    final isAboveThreshold = b != null && displayHours != null &&
        displayHours > b.thresholdScreenTime;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isAboveThreshold
            ? const Color(0xFF2A1A0A)
            : const Color(0xFF232325),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isAboveThreshold
              ? Colors.orange.withOpacity(0.5)
              : Colors.white12,
        ),
      ),
      child: Row(children: [
        Icon(
          Icons.phone_android_outlined,
          color: isAboveThreshold ? Colors.orange : const Color(0xFF8A5CE6),
          size: 22,
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Screen Time Today  (live)',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
            if (b != null)
              Text(
                'avg: ${b.avgScreenTime.toStringAsFixed(1)}h  '
                '· threshold: ${b.thresholdScreenTime.toStringAsFixed(1)}h',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
          ],
        )),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            displayHours != null
                ? '${displayHours.toStringAsFixed(1)} h'
                : '--',
            style: TextStyle(
              color: isAboveThreshold ? Colors.orange : Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          if (isAboveThreshold)
            const Text('above normal',
                style: TextStyle(color: Colors.orange, fontSize: 10)),
        ]),
      ]),
    );
  }

  Widget _baselineCard() {
    if (_baseline == null) return const SizedBox.shrink();
    final b = _baseline!;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFF8A5CE6).withOpacity(0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.person_outline,
              color: Color(0xFF8A5CE6), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Your Personal Baseline',
              style: const TextStyle(
                  color: Color(0xFF8A5CE6),
                  fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: b.daysOfData >= 10
                  ? Colors.green.withOpacity(0.2)
                  : Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              b.dataQuality,
              style: TextStyle(
                color: b.daysOfData >= 10 ? Colors.green : Colors.orange,
                fontSize: 10,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        // Averages
        _bRow('Avg screen time',
            '${b.avgScreenTime.toStringAsFixed(1)} h/day'),
        _bRow('Avg social usage',
            '${(b.avgSocialRatio * 100).toStringAsFixed(0)}%'),
        _bRow('Avg work usage',
            '${(b.avgWorkRatio * 100).toStringAsFixed(0)}%'),
        _bRow('Avg app switches',
            '${b.avgAppSwitches.toStringAsFixed(0)} /hr'),
        const Divider(color: Colors.white12, height: 16),
        // Dynamic thresholds
        Row(children: [
          const Icon(Icons.tune, color: Colors.white38, size: 14),
          const SizedBox(width: 6),
          const Text('Dynamic Thresholds  (auto-computed from your data)',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
        const SizedBox(height: 6),
        _bRow('Screen time threshold',
            '${b.thresholdScreenTime.toStringAsFixed(1)} h'),
        _bRow('Social ratio threshold',
            '${(b.thresholdSocialRatio * 100).toStringAsFixed(0)}%'),
        _bRow('App switches threshold',
            '${b.thresholdAppSwitches.toStringAsFixed(0)} /hr'),
        const SizedBox(height: 6),
        Text(
          _daysSinceInstall > 0
              ? 'BrainLag installed $_daysSinceInstall day(s) ago. '
                'Thresholds improve with more data.'
              : '',
          style: const TextStyle(color: Colors.white24, fontSize: 10),
        ),
      ]),
    );
  }

  Widget _bRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(children: [
          Expanded(child: Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 13))),
          Text(value, style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      );

  Widget _lineChart({
    required String title,
    required List<FlSpot> spots,
    required double maxY,
    Color color = const Color(0xFF8A5CE6),
    double? thresholdY,
    double? avgY,
  }) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF232325),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(
              color: Colors.white,
              fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          spots.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No data yet',
                        style: TextStyle(color: Colors.white38))))
              : SizedBox(
                  height: 200,
                  child: LineChart(LineChartData(
                    minX: 0,
                    maxX: (spots.length - 1).toDouble().clamp(1, 13),
                    minY: 0, maxY: maxY,
                    gridData: FlGridData(
                      show: true, drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) =>
                          const FlLine(color: Colors.white12, strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                    extraLinesData: ExtraLinesData(
                      horizontalLines: [
                        if (thresholdY != null)
                          HorizontalLine(
                            y: thresholdY,
                            color: Colors.orange.withOpacity(0.8),
                            strokeWidth: 1.5,
                            dashArray: [6, 4],
                            label: HorizontalLineLabel(
                              show: true,
                              alignment: Alignment.topRight,
                              labelResolver: (_) => 'threshold',
                              style: const TextStyle(
                                  color: Colors.orange, fontSize: 9),
                            ),
                          ),
                        if (avgY != null)
                          HorizontalLine(
                            y: avgY,
                            color: Colors.green.withOpacity(0.5),
                            strokeWidth: 1,
                            dashArray: [4, 4],
                            label: HorizontalLineLabel(
                              show: true,
                              alignment: Alignment.bottomRight,
                              labelResolver: (_) => 'your avg',
                              style: const TextStyle(
                                  color: Colors.green, fontSize: 9),
                            ),
                          ),
                      ],
                    ),
                    titlesData: FlTitlesData(
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true, reservedSize: 30,
                          getTitlesWidget: (v, _) => Text(
                              v.toStringAsFixed(1),
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 9)),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, _) {
                            final i = v.toInt();
                            if (i < 0 || i >= _history.length)
                              return const SizedBox.shrink();
                            final ago = _history[i].daysAgo;
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                ago == 0 ? 'Today' : '-${ago}d',
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 9)),
                            );
                          },
                        ),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots, isCurved: true,
                        color: color, barWidth: 2.5,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                            radius: 3, color: color,
                            strokeWidth: 1, strokeColor: Colors.white24,
                          ),
                        ),
                        belowBarData: BarAreaData(
                            show: true, color: color.withOpacity(0.12)),
                      ),
                    ],
                  )),
                ),
        ]),
      );

  Widget _permissionPrompt() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline,
                  color: Colors.white38, size: 64),
              const SizedBox(height: 20),
              const Text('Usage Access Required',
                  style: TextStyle(color: Colors.white,
                      fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              const Text(
                'BrainLag reads your Digital Wellbeing data to detect '
                'burnout patterns. No data leaves your device without '
                'your consent.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  await UsageService.instance.openSettings();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF45199D),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Open Settings',
                    style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _checkPermissionAndLoad,
                child: const Text("I've granted it — retry",
                    style: TextStyle(color: Color(0xFF8A5CE6))),
              ),
            ],
          ),
        ),
      );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final today      = _history.isNotEmpty ? _history.first : null;
    final todayScore = _scores[0];
    final todayLevel = _levels[0] ?? '--';
    final alerts     = _deviationAlerts;
    final b          = _baseline;

    final scoreSpots = _scores.entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList()..sort((a, b) => a.x.compareTo(b.x));

    final screenSpots = _history.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.screenTimeHours))
        .toList();

    final socialSpots = _history.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.socialAppRatio))
        .toList();

    final switchSpots = _history.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.appSwitchesPerHour))
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0F),
        title: const Text('Continuous Monitoring',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: _isFetching
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.refresh, color: Colors.white),
            onPressed: _isFetching ? null : _checkPermissionAndLoad,
          ),
        ],
      ),
      body: !_hasPermission
          ? _permissionPrompt()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // Status
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1C),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.access_time,
                          color: Colors.white38, size: 14),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_statusMsg,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12))),
                    ]),
                  ),

                  // Baseline card with dynamic thresholds
                  _baselineCard(),

                  // Burnout result
                  _infoCard(
                    title: "Today's Burnout Risk",
                    value: todayScore != null ? todayLevel : '--',
                    icon: Icons.health_and_safety_outlined,
                    valueColor: todayScore != null
                        ? _levelColor(todayLevel) : null,
                  ),
                  _infoCard(
                    title: 'Burnout Score  (0 – 1)',
                    value: todayScore?.toStringAsFixed(2) ?? '--',
                    icon: Icons.show_chart,
                    valueColor: todayScore != null
                        ? _levelColor(todayLevel) : null,
                  ),

                  // LIVE screen time — highlighted card
                  _liveScreenTimeCard(),

                  // App switches
                  _infoCard(
                    title: 'App Switches / hr',
                    value: today != null
                        ? today.appSwitchesPerHour.toStringAsFixed(1)
                        : '--',
                    subtitle: b != null
                        ? 'avg: ${b.avgAppSwitches.toStringAsFixed(0)}/hr  '
                          '· threshold: ${b.thresholdAppSwitches.toStringAsFixed(0)}/hr'
                        : null,
                    icon: Icons.swap_horiz_outlined,
                    valueColor: (today != null && b != null &&
                            today.appSwitchesPerHour > b.thresholdAppSwitches)
                        ? Colors.orange : null,
                  ),

                  // Social usage
                  _infoCard(
                    title: 'Social App Usage',
                    value: today != null
                        ? '${(today.socialAppRatio * 100).toStringAsFixed(0)}%'
                        : '--',
                    subtitle: b != null
                        ? 'avg: ${(b.avgSocialRatio * 100).toStringAsFixed(0)}%  '
                          '· threshold: ${(b.thresholdSocialRatio * 100).toStringAsFixed(0)}%'
                        : null,
                    icon: Icons.people_outline,
                    valueColor: (today != null && b != null &&
                            today.socialAppRatio > b.thresholdSocialRatio)
                        ? Colors.orange : null,
                  ),

                  // Work usage
                  _infoCard(
                    title: 'Work App Usage',
                    value: today != null
                        ? '${(today.workAppRatio * 100).toStringAsFixed(0)}%'
                        : '--',
                    subtitle: b != null
                        ? 'avg: ${(b.avgWorkRatio * 100).toStringAsFixed(0)}%'
                        : null,
                    icon: Icons.work_outline,
                  ),

                  const SizedBox(height: 6),

                  // Deviation alerts
                  if (alerts.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A1A0A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.orange.withOpacity(0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.warning_amber_outlined,
                                color: Colors.orange, size: 18),
                            SizedBox(width: 8),
                            Text('Deviation from Your Normal',
                                style: TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w700)),
                          ]),
                          const SizedBox(height: 10),
                          ...alerts.map((a) => Padding(
                                padding: const EdgeInsets.only(bottom: 5),
                                child: Text(a,
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13)),
                              )),
                        ],
                      ),
                    ),

                  // Charts
                  _lineChart(
                    title: 'Burnout Score Trend',
                    spots: scoreSpots,
                    maxY: 1.0,
                    color: Colors.deepOrangeAccent,
                  ),
                  const SizedBox(height: 14),
                  _lineChart(
                    title: 'Screen Time (hours)',
                    spots: screenSpots,
                    maxY: 16,
                    color: const Color(0xFF8A5CE6),
                    thresholdY: b?.thresholdScreenTime,
                    avgY: b?.avgScreenTime,
                  ),
                  const SizedBox(height: 14),
                  _lineChart(
                    title: 'App Switches / hr',
                    spots: switchSpots,
                    maxY: 80,
                    color: Colors.tealAccent,
                    thresholdY: b?.thresholdAppSwitches,
                    avgY: b?.avgAppSwitches,
                  ),
                  const SizedBox(height: 14),
                  _lineChart(
                    title: 'Social App Usage',
                    spots: socialSpots,
                    maxY: 1.0,
                    color: Colors.pinkAccent,
                    thresholdY: b?.thresholdSocialRatio,
                    avgY: b?.avgSocialRatio,
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }
}