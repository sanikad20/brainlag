import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'api_service.dart';

/// Stores one day's result in memory.
/// TODO: swap List for Hive/SharedPreferences for persistence across app restarts.
class _DayRecord {
  final DateTime date;
  final double   burnoutScore;
  final String   burnoutLevel;
  final double   screenTime;
  final double   socialRatio;
  final double   workRatio;
  final double   sleepHours;
  final double   appSwitches;

  const _DayRecord({
    required this.date,
    required this.burnoutScore,
    required this.burnoutLevel,
    required this.screenTime,
    required this.socialRatio,
    required this.workRatio,
    required this.sleepHours,
    required this.appSwitches,
  });
}

class ContinuousMonitoringScreen extends StatefulWidget {
  const ContinuousMonitoringScreen({super.key});

  @override
  State<ContinuousMonitoringScreen> createState() =>
      _ContinuousMonitoringScreenState();
}

class _ContinuousMonitoringScreenState
    extends State<ContinuousMonitoringScreen> {

  final List<_DayRecord> _history = [];
  bool   _isFetching = false;
  String _statusMsg  = 'Tap refresh to fetch today\'s data.';
  Timer? _autoTimer;

  // ─── Build usage objects from Android UsageStats ──────────────────────────
  // These two methods are where you plug in your MethodChannel data.
  // Right now they return realistic demo values.

  DayUsage _todayUsage() {
    // TODO: replace with real values from MethodChannel 'brainlag/usage_access'
    // The channel already collects screenTime and appSwitches — extend it to
    // also return socialAppRatio / workAppRatio by categorising package names.
    return const DayUsage(
      screenTimeHours:     6.5,
      appSwitchesPerHour:  28,
      uniqueAppsPerDay:    18,
      socialAppRatio:      0.40,  // Instagram + WhatsApp + Twitter time / total
      workAppRatio:        0.25,  // Gmail + Docs + Slack time / total
      entertainmentRatio:  0.20,  // YouTube + Netflix time / total
      wellnessRatio:       0.05,
      sleepHours:          6.0,
      sleepQuality:        3,
      exerciseMinPerWeek:  90,
      socialHoursPerWeek:  12,
      callCount:           4,
      missedCallRatio:     0.2,
      smsCount:            15,
    );
  }

  DayUsage _yesterdayUsage() {
    // TODO: load yesterday's stored values from SharedPreferences / Hive
    return const DayUsage(
      screenTimeHours:     4.5,
      appSwitchesPerHour:  18,
      uniqueAppsPerDay:    12,
      socialAppRatio:      0.20,
      workAppRatio:        0.45,
      entertainmentRatio:  0.15,
      wellnessRatio:       0.10,
      sleepHours:          7.5,
      sleepQuality:        4,
      exerciseMinPerWeek:  120,
      socialHoursPerWeek:  10,
      callCount:           6,
      missedCallRatio:     0.05,
      smsCount:            22,
    );
  }

  // ─── Fetch → predict → store ──────────────────────────────────────────────

  Future<void> _refresh() async {
    if (_isFetching) return;
    setState(() {
      _isFetching = true;
      _statusMsg  = 'Analysing 2-day behaviour…';
    });

    try {
      final result = await ApiService.instance.predictTwoDay(
        day1: _yesterdayUsage(),
        day2: _todayUsage(),
      );

      final today = _todayUsage();
      final record = _DayRecord(
        date:         DateTime.now(),
        burnoutScore: result.score,
        burnoutLevel: result.level,
        screenTime:   today.screenTimeHours,
        socialRatio:  today.socialAppRatio,
        workRatio:    today.workAppRatio,
        sleepHours:   today.sleepHours,
        appSwitches:  today.appSwitchesPerHour,
      );

      setState(() {
        if (_history.length >= 7) _history.removeAt(0);
        _history.add(record);
        _statusMsg = 'Updated at ${_fmt(DateTime.now())}';
      });
    } catch (e) {
      setState(() => _statusMsg = 'Error: $e');
    } finally {
      setState(() => _isFetching = false);
    }
  }

  String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _refresh();
    _autoTimer = Timer.periodic(const Duration(minutes: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  // ─── Deviation detection ──────────────────────────────────────────────────

  List<String> get _deviationAlerts {
    if (_history.length < 2) return [];
    final prev = _history[_history.length - 2];
    final curr = _history.last;
    final alerts = <String>[];

    if (curr.screenTime  - prev.screenTime  >  1.5)
      alerts.add('📱 Screen time up ${(curr.screenTime - prev.screenTime).toStringAsFixed(1)}h vs yesterday');
    if (curr.socialRatio - prev.socialRatio >  0.15)
      alerts.add('📲 Social app usage spiked vs yesterday');
    if (prev.workRatio   - curr.workRatio   >  0.15)
      alerts.add('💼 Work app usage dropped vs yesterday');
    if (prev.sleepHours  - curr.sleepHours  >  1.0)
      alerts.add('😴 Slept ${(prev.sleepHours - curr.sleepHours).toStringAsFixed(1)}h less than yesterday');
    if (curr.appSwitches - prev.appSwitches >  15)
      alerts.add('🔀 App switching increased significantly today');

    return alerts;
  }

  // ─── Chart helper ─────────────────────────────────────────────────────────

  Widget _lineChart({
    required String title,
    required List<FlSpot> spots,
    required double maxY,
    Color color = const Color(0xFF8A5CE6),
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF232325),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(
            color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        spots.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No data yet',
                      style: TextStyle(color: Colors.white38)),
                ))
            : SizedBox(
                height: 190,
                child: LineChart(LineChartData(
                  minX: 0,
                  maxX: (_history.length - 1).toDouble().clamp(1, 6),
                  minY: 0,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true, drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        const FlLine(color: Colors.white12, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (v, _) => Text(
                          v.toStringAsFixed(1),
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 9),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= _history.length)
                            return const SizedBox.shrink();
                          final d = _history[i].date;
                          return Text('${d.day}/${d.month}',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 9));
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: color,
                      barWidth: 2.5,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                          show: true, color: color.withOpacity(0.15)),
                    ),
                  ],
                )),
              ),
      ]),
    );
  }

  // ─── Info card ────────────────────────────────────────────────────────────

  Widget _infoCard({
    required String title,
    required String value,
    required IconData icon,
    Color? valueColor,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF232325),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(children: [
          Icon(icon, color: const Color(0xFF8A5CE6), size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(title,
              style: const TextStyle(color: Colors.white70))),
          Text(value,
              style: TextStyle(
                  color: valueColor ?? Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
        ]),
      );

  Color _levelColor(String level) {
    if (level.contains('Low'))      return Colors.green;
    if (level.contains('Moderate')) return Colors.orange;
    if (level.contains('High'))     return Colors.red;
    return Colors.white;
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final latest = _history.isNotEmpty ? _history.last : null;
    final alerts = _deviationAlerts;

    final scoreSpots = _history
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.burnoutScore))
        .toList();

    final screenSpots = _history
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.screenTime))
        .toList();

    final socialSpots = _history
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.socialRatio))
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
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.refresh, color: Colors.white),
            onPressed: _isFetching ? null : _refresh,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Status bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1C),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              const Icon(Icons.access_time, color: Colors.white38, size: 14),
              const SizedBox(width: 8),
              Text(_statusMsg,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ),

          // Summary cards
          _infoCard(
            title: 'Current Burnout Risk',
            value: latest?.burnoutLevel ?? '-- --',
            icon: Icons.health_and_safety_outlined,
            valueColor: latest != null
                ? _levelColor(latest.burnoutLevel)
                : null,
          ),
          _infoCard(
            title: 'Burnout Score (0 – 1)',
            value: latest != null
                ? latest.burnoutScore.toStringAsFixed(2)
                : '--',
            icon: Icons.show_chart,
            valueColor: latest != null
                ? _levelColor(latest.burnoutLevel)
                : null,
          ),
          _infoCard(
            title: 'Screen Time Today',
            value: latest != null
                ? '${latest.screenTime.toStringAsFixed(1)} h'
                : '--',
            icon: Icons.phone_android_outlined,
          ),
          _infoCard(
            title: 'Social App Usage',
            value: latest != null
                ? '${(latest.socialRatio * 100).toStringAsFixed(0)}%'
                : '--',
            icon: Icons.people_outline,
          ),
          _infoCard(
            title: 'Work App Usage',
            value: latest != null
                ? '${(latest.workRatio * 100).toStringAsFixed(0)}%'
                : '--',
            icon: Icons.work_outline,
          ),

          const SizedBox(height: 6),

          // Deviation alerts
          if (alerts.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF2A1A0A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.orange.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.warning_amber_outlined,
                        color: Colors.orange, size: 18),
                    SizedBox(width: 8),
                    Text('Behaviour Change Detected',
                        style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 10),
                  ...alerts.map((a) => Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(a,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                      )),
                ],
              ),
            ),
          ],

          // Charts
          _lineChart(
            title: 'Burnout Score Trend',
            spots: scoreSpots,
            maxY: 1.0,
            color: Colors.deepOrangeAccent,
          ),
          const SizedBox(height: 14),
          _lineChart(
            title: 'Screen Time Trend (hours)',
            spots: screenSpots,
            maxY: 16,
            color: const Color(0xFF8A5CE6),
          ),
          const SizedBox(height: 14),
          _lineChart(
            title: 'Social App Usage Trend',
            spots: socialSpots,
            maxY: 1.0,
            color: Colors.pinkAccent,
          ),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }
}