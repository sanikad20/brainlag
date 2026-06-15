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

  List<DayUsageRaw> _history   = [];
  PersonalBaseline? _baseline;
  double?           _liveScreenTime;
  int               _daysSinceInstall = 0;

  final Map<int, double> _scores = {};
  final Map<int, String> _levels = {};

  Timer? _autoTimer;
  Timer? _liveTimer;

  @override
  void initState() {
    super.initState();
    _init();
    _autoTimer = Timer.periodic(
        const Duration(minutes: 30), (_) => _init());
    _liveTimer = Timer.periodic(
        const Duration(minutes: 5), (_) => _refreshLive());
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final ok = await UsageService.instance.hasPermission();
    setState(() => _hasPermission = ok);
    if (ok) await _loadAll();
    else     setState(() => _statusMsg = 'Grant usage access to continue.');
  }

  Future<void> _refreshLive() async {
    if (!_hasPermission) return;
    final h = await UsageService.instance.fetchLiveScreenTime();
    if (mounted) setState(() => _liveScreenTime = h);
  }

  // ── Main load ─────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    if (_isFetching) return;
    setState(() {
      _isFetching = true;
      _statusMsg  = 'Reading 7-day Digital Wellbeing data…';
    });

    try {
      await UsageService.instance.getInstallDate();

      // Fetch 7 days from Android Digital Wellbeing
      final history = await UsageService.instance.fetchHistory(
          forceRefresh: true);

      // Also get live screen time
      final live = await UsageService.instance.fetchLiveScreenTime();

      if (history.isEmpty) {
        setState(() {
          _statusMsg       = 'No usage data found. '
              'Make sure Usage Access is granted.';
          _isFetching      = false;
        });
        return;
      }

      final baseline = UsageService.instance.baseline!;

      setState(() {
        _history          = history;
        _baseline         = baseline;
        _liveScreenTime   = live;
        _daysSinceInstall = UsageService.instance.daysSinceInstall;
        _statusMsg        = 'Analysing ${history.length}-day pattern…';
      });

      // Predict for consecutive day pairs
      _scores.clear();
_levels.clear();

if (history.length >= 7) {

  try {

    final days = history
        .take(7)
        .map((d) =>
            _toApi(d, baseline))
        .toList();

    final result =
        await ApiService.instance
            .predictSevenDay(
                days: days);

    if (mounted) {

      setState(() {

        _scores[0] =
            result.score;

        _levels[0] =
            result.level;
      });
    }

  } catch (e) {

    debugPrint(
        'Prediction error: $e');
  }
}

      setState(() => _statusMsg =
          'Updated ${_fmt(DateTime.now())}  · ${history.length} days');

    } catch (e) {
      setState(() => _statusMsg = 'Error: $e');
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  DayUsage _toApi(DayUsageRaw d, PersonalBaseline b) => DayUsage(
        screenTimeHours:    d.screenTimeHours,
        appSwitchesPerHour: d.appSwitchesPerHour.toDouble(),
        uniqueAppsPerDay:   d.uniqueAppsPerDay.toDouble(),
        socialAppRatio:     d.socialAppRatio,
        workAppRatio:       d.workAppRatio,
        entertainmentRatio: d.entertainmentRatio,
        wellnessRatio:      d.wellnessRatio,
        sleepHours:         7.0,
        sleepQuality:       3.0,
        exerciseMinPerWeek: 120.0,
        socialHoursPerWeek: 10.0,
        callCount:          5.0,
        missedCallRatio:    0.1,
        smsCount:           20.0,
      );

  String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2,'0')}:'
      '${t.minute.toString().padLeft(2,'0')}';

  // ── Deviation alerts ──────────────────────────────────────────────────────

  List<String> get _alerts {
    if (_history.isEmpty || _baseline == null) return [];
    final d = _history.first;
    final b = _baseline!;
    final a = <String>[];

    if (d.screenTimeHours > b.thresholdScreenTime)
      a.add('📱 Screen time ${d.screenTimeHours.toStringAsFixed(1)}h '
          '> your threshold ${b.thresholdScreenTime.toStringAsFixed(1)}h');

    if (d.socialAppRatio > b.thresholdSocialRatio)
      a.add('📲 Social apps ${(d.socialAppRatio*100).toStringAsFixed(0)}% '
          '> threshold ${(b.thresholdSocialRatio*100).toStringAsFixed(0)}%');

    if (d.appSwitchesPerHour > b.thresholdAppSwitches)
      a.add('🔀 App switches ${d.appSwitchesPerHour}/hr '
          '> threshold ${b.thresholdAppSwitches}/hr');

    if (b.screenZScore(d.screenTimeHours) > 1.5)
      a.add('⚠️ Screen time is '
          '${b.screenZScore(d.screenTimeHours).toStringAsFixed(1)}σ '
          'above your personal average');

    if (b.socialZScore(d.socialAppRatio) > 1.5)
      a.add('⚠️ Social usage is '
          '${b.socialZScore(d.socialAppRatio).toStringAsFixed(1)}σ '
          'above your normal');

    if (d.workAppRatio < b.avgWorkRatio * 0.6 && b.avgWorkRatio > 0.1)
      a.add('💼 Work app usage dropped vs your normal');

    return a;
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  Color _lvlColor(String l) {
    if (l.contains('Low'))      return Colors.green;
    if (l.contains('Moderate')) return Colors.orange;
    if (l.contains('High'))     return Colors.red;
    return Colors.white;
  }

  Widget _card({
    required String   title,
    required String   value,
    required IconData icon,
    Color?   valueColor,
    String?  subtitle,
    bool     highlight = false,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: highlight
              ? const Color(0xFF2A1A0A)
              : const Color(0xFF232325),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: highlight
                ? Colors.orange.withOpacity(0.5)
                : Colors.white12,
          ),
        ),
        child: Row(children: [
          Icon(icon,
            color: highlight ? Colors.orange : const Color(0xFF8A5CE6),
            size: 22),
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
          Text(value,
              style: TextStyle(
                  color: valueColor ?? Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
        ]),
      );

  // Chart with correct date labels on x-axis
  Widget _chart({
    required String       title,
    required List<FlSpot> spots,
    required double       maxY,
    bool                  isInt  = false,
    Color  color    = const Color(0xFF8A5CE6),
    double? threshY,
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
          Text(title,
              style: const TextStyle(
                  color: Colors.white, fontSize: 15,
                  fontWeight: FontWeight.w600)),
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
                    maxX: (spots.length - 1).toDouble().clamp(1.0, 6.0),
                    minY: 0, maxY: maxY,
                    gridData: FlGridData(
                      show: true, drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) =>
                          const FlLine(color: Colors.white12, strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                    extraLinesData: ExtraLinesData(horizontalLines: [
                      if (threshY != null)
                        HorizontalLine(
                          y: threshY,
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
                          color: Colors.green.withOpacity(0.6),
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
                    ]),
                    titlesData: FlTitlesData(
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true, reservedSize: 32,
                          getTitlesWidget: (v, _) => Text(
                            isInt
                                ? v.toInt().toString()
                                : v.toStringAsFixed(1),
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 9)),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          getTitlesWidget: (v, _) {
                            final i = v.toInt();
                            if (i < 0 || i >= _history.length)
                              return const SizedBox.shrink();
                            // Show actual date label from the data
                            final day = _history[i];
                            final label = day.daysAgo == 0
                                ? 'Today'
                                : day.dateLabel;
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(label,
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
                          getDotPainter: (s, _, __, ___) =>
                              FlDotCirclePainter(
                                radius: 3, color: color,
                                strokeWidth: 1,
                                strokeColor: Colors.white24,
                              ),
                        ),
                        belowBarData: BarAreaData(
                            show: true,
                            color: color.withOpacity(0.12)),
                      ),
                    ],
                  )),
                ),
        ]),
      );

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
          const Expanded(
            child: Text('Your Personal Baseline  (7 days)',
                style: TextStyle(color: Color(0xFF8A5CE6),
                    fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: b.daysOfData >= 5
                  ? Colors.green.withOpacity(0.2)
                  : Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(b.qualityLabel,
                style: TextStyle(
                    color: b.daysOfData >= 5 ? Colors.green : Colors.orange,
                    fontSize: 10)),
          ),
        ]),
        const SizedBox(height: 10),
        _bRow('Avg screen time',
            '${b.avgScreenTime.toStringAsFixed(1)} h/day'),
        _bRow('Avg social usage',
            '${(b.avgSocialRatio*100).toStringAsFixed(0)}%'),
        _bRow('Avg work usage',
            '${(b.avgWorkRatio*100).toStringAsFixed(0)}%'),
        _bRow('Avg app switches',
            '${b.avgAppSwitchesPerHour} /hr'),
        const Divider(color: Colors.white12, height: 16),
        Row(children: [
          const Icon(Icons.tune, color: Colors.white38, size: 14),
          const SizedBox(width: 6),
          const Text('Dynamic Thresholds',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
        const SizedBox(height: 6),
        _bRow('Screen time',
            '${b.thresholdScreenTime.toStringAsFixed(1)} h'),
        _bRow('Social ratio',
            '${(b.thresholdSocialRatio*100).toStringAsFixed(0)}%'),
        _bRow('App switches',
            '${b.thresholdAppSwitches} /hr'),
        if (_daysSinceInstall > 0) ...[
          const SizedBox(height: 6),
          Text(
            'BrainLag installed $_daysSinceInstall day(s) ago. '
            'Accuracy improves each day.',
            style: const TextStyle(color: Colors.white24, fontSize: 10),
          ),
        ],
      ]),
    );
  }

  Widget _bRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(children: [
          Expanded(child: Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 13))),
          Text(value, style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      );

  Widget _permissionScreen() => Center(
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
                'burnout. No data is shared without your consent.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: UsageService.instance.openSettings,
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
                onPressed: _init,
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
    final b          = _baseline;
    final alerts     = _alerts;

    // Live screen time — prefer live value, fallback to history
    final screenDisplay = _liveScreenTime ?? today?.screenTimeHours;
    final screenAbove   = b != null && screenDisplay != null &&
        screenDisplay > b.thresholdScreenTime;

    // Chart spots — x=0 is today, x=6 is 6 days ago
    List<FlSpot> makeSpots(double Function(DayUsageRaw) fn) =>
    _history.asMap().entries
        .map((e) => FlSpot(
              e.key.toDouble(),
              fn(e.value),
            ))
        .toList();
    final scoreSpots = _scores.entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList()..sort((a, b) => a.x.compareTo(b.x));

    final screenSpots  = makeSpots((d) => d.screenTimeHours);
    final socialSpots  = makeSpots((d) => d.socialAppRatio);
    final switchSpots  = _history.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(),
            e.value.appSwitchesPerHour.toDouble()))
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
            onPressed: _isFetching ? null : _init,
          ),
        ],
      ),
      body: !_hasPermission
          ? _permissionScreen()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // Status bar
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

                  // Baseline
                  _baselineCard(),

                  // Burnout risk
                  _card(
                    title: "Today's Burnout Risk",
                    value: todayScore != null ? todayLevel : '--',
                    icon: Icons.health_and_safety_outlined,
                    valueColor: todayScore != null
                        ? _lvlColor(todayLevel) : null,
                  ),
                  _card(
                    title: 'Burnout Score  (0–1)',
                    value: todayScore?.toStringAsFixed(2) ?? '--',
                    icon: Icons.show_chart,
                    valueColor: todayScore != null
                        ? _lvlColor(todayLevel) : null,
                  ),

                  // Live screen time
                  _card(
                    title: 'Screen Time Today  (live)',
                    value: screenDisplay != null
                        ? '${screenDisplay.toStringAsFixed(1)} h'
                        : '--',
                    icon: Icons.phone_android_outlined,
                    valueColor: screenAbove ? Colors.orange : null,
                    subtitle: b != null
                        ? 'avg: ${b.avgScreenTime.toStringAsFixed(1)}h  '
                          '· threshold: ${b.thresholdScreenTime.toStringAsFixed(1)}h'
                        : null,
                    highlight: screenAbove,
                  ),

                  // App switches — whole number
                  _card(
                    title: 'App Switches / hr',
                    value: today != null
                        ? '${today.appSwitchesPerHour}'   // whole number
                        : '--',
                    icon: Icons.swap_horiz_outlined,
                    subtitle: b != null
                        ? 'avg: ${b.avgAppSwitchesPerHour}/hr  '
                          '· threshold: ${b.thresholdAppSwitches}/hr'
                        : null,
                    valueColor: (today != null && b != null &&
                            today.appSwitchesPerHour > b.thresholdAppSwitches)
                        ? Colors.orange : null,
                    highlight: today != null && b != null &&
                        today.appSwitchesPerHour > b.thresholdAppSwitches,
                  ),

                  // Social usage
                  _card(
                    title: 'Social App Usage',
                    value: today != null
                        ? '${(today.socialAppRatio*100).toStringAsFixed(0)}%'
                        : '--',
                    icon: Icons.people_outline,
                    subtitle: b != null
                        ? 'avg: ${(b.avgSocialRatio*100).toStringAsFixed(0)}%  '
                          '· threshold: ${(b.thresholdSocialRatio*100).toStringAsFixed(0)}%'
                        : null,
                    valueColor: (today != null && b != null &&
                            today.socialAppRatio > b.thresholdSocialRatio)
                        ? Colors.orange : null,
                  ),

                  // Work usage
                  _card(
                    title: 'Work App Usage',
                    value: today != null
                        ? '${(today.workAppRatio*100).toStringAsFixed(0)}%'
                        : '--',
                    icon: Icons.work_outline,
                    subtitle: b != null
                        ? 'avg: ${(b.avgWorkRatio*100).toStringAsFixed(0)}%'
                        : null,
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
                                style: TextStyle(color: Colors.orange,
                                    fontWeight: FontWeight.w700)),
                          ]),
                          const SizedBox(height: 10),
                          ...alerts.map((a) => Padding(
                                padding: const EdgeInsets.only(bottom: 5),
                                child: Text(a, style: const TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                              )),
                        ],
                      ),
                    ),

                  // Charts with real date labels
                  _chart(
                    title: 'Burnout Score  (7 days)',
                    spots: scoreSpots, maxY: 1.0,
                    color: Colors.deepOrangeAccent,
                  ),
                  const SizedBox(height: 14),
                  _chart(
                    title: 'Screen Time  (hours)',
                    spots: screenSpots, maxY: 14,
                    color: const Color(0xFF8A5CE6),
                    threshY: b?.thresholdScreenTime,
                    avgY:    b?.avgScreenTime,
                  ),
                  const SizedBox(height: 14),
                  _chart(
                    title: 'App Switches / hr',
                    spots: switchSpots, maxY: 60,
                    isInt: true,
                    color: Colors.tealAccent,
                    threshY: b?.thresholdAppSwitches.toDouble(),
                    avgY:    b?.avgAppSwitchesPerHour.toDouble(),
                  ),
                  const SizedBox(height: 14),
                  _chart(
                    title: 'Social App Usage',
                    spots: socialSpots, maxY: 1.0,
                    color: Colors.pinkAccent,
                    threshY: b?.thresholdSocialRatio,
                    avgY:    b?.avgSocialRatio,
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }
}