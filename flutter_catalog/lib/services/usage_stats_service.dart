import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usage_stats_new/usage_stats.dart';

class DailyUsageSummary {
  final DateTime date;
  final double screenTimeHours;
  final int sessions;
  final double lateNightUsageHours;
  final int appSwitches;

  const DailyUsageSummary({
    required this.date,
    required this.screenTimeHours,
    required this.sessions,
    required this.lateNightUsageHours,
    required this.appSwitches,
  });

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'screen_time_hours': screenTimeHours,
        'sessions': sessions,
        'late_night_usage_hours': lateNightUsageHours,
        'app_switches': appSwitches,
      };

  factory DailyUsageSummary.fromJson(Map<String, dynamic> json) {
    return DailyUsageSummary(
      date: DateTime.parse(json['date'] as String),
      screenTimeHours: (json['screen_time_hours'] as num).toDouble(),
      sessions: (json['sessions'] as num).toInt(),
      lateNightUsageHours: (json['late_night_usage_hours'] as num).toDouble(),
      appSwitches: (json['app_switches'] as num).toInt(),
    );
  }
}

class UsageStatsService {
  static const String _storageKey = 'brainlag_daily_usage_history';

  Future<List<DailyUsageSummary>> collectLast7Days() async {
    final now = DateTime.now();
    final List<DailyUsageSummary> result = [];

    for (int i = 6; i >= 0; i--) {
      final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final summary = await collectForSingleDay(day);
      result.add(summary);
    }

    await saveHistory(result);
    return result;
  }

  Future<DailyUsageSummary> collectForSingleDay(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    final usageInfoList = await UsageStats.queryUsageStats(
      start,
      end,
    );

    final eventList = await UsageStats.queryEvents(
      start,
      end,
    );

    double totalForegroundMs = 0;
    int appSwitches = 0;
    int sessions = 0;
    double lateNightForegroundMs = 0;

    for (final usage in usageInfoList) {
      final totalTime = int.tryParse(usage.totalTimeInForeground ?? '0') ?? 0;
      totalForegroundMs += totalTime;
    }

    String? previousPackage;
    bool hadResumeEvent = false;

    for (final event in eventList) {
      final packageName = event.packageName ?? '';
      final eventType = event.eventType ?? '';
      final timeStampMs = int.tryParse(event.timeStamp ?? '0') ?? 0;

      if (packageName.isEmpty || timeStampMs == 0) continue;

      final eventTime = DateTime.fromMillisecondsSinceEpoch(timeStampMs);
      final hour = eventTime.hour;

      final isLateNight = hour >= 23 || hour < 5;
      if (isLateNight &&
          (eventType.contains('MOVE_TO_FOREGROUND') ||
              eventType.contains('ACTIVITY_RESUMED'))) {
        lateNightForegroundMs += 300000;
      }

      final isForegroundEvent = eventType.contains('MOVE_TO_FOREGROUND') ||
          eventType.contains('ACTIVITY_RESUMED');

      if (isForegroundEvent) {
        sessions++;

        if (previousPackage != null && previousPackage != packageName) {
          appSwitches++;
        }
        previousPackage = packageName;
        hadResumeEvent = true;
      }
    }

    if (!hadResumeEvent && totalForegroundMs > 0) {
      sessions = max(1, (totalForegroundMs / (8 * 60 * 1000)).round());
    }

    final screenTimeHours = totalForegroundMs / (1000 * 60 * 60);
    final lateNightUsageHours = lateNightForegroundMs / (1000 * 60 * 60);

    return DailyUsageSummary(
      date: start,
      screenTimeHours: double.parse(screenTimeHours.toStringAsFixed(2)),
      sessions: sessions,
      lateNightUsageHours: double.parse(lateNightUsageHours.toStringAsFixed(2)),
      appSwitches: appSwitches,
    );
  }

  Future<void> saveHistory(List<DailyUsageSummary> history) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = history.map((e) => e.toJson().toString()).toList();
    await prefs.setStringList(_storageKey, encoded);
  }

  Future<List<DailyUsageSummary>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? [];
    return raw.map((entry) {
      final map = _parseStoredMap(entry);
      return DailyUsageSummary.fromJson(map);
    }).toList();
  }

  Map<String, dynamic> _parseStoredMap(String text) {
    final cleaned = text.substring(1, text.length - 1);
    final parts = cleaned.split(', ');
    final map = <String, dynamic>{};

    for (final part in parts) {
      final idx = part.indexOf(': ');
      if (idx == -1) continue;
      final key = part.substring(0, idx);
      final value = part.substring(idx + 2);

      if (key == 'date') {
        map[key] = value;
      } else if (key == 'sessions' || key == 'app_switches') {
        map[key] = int.tryParse(value) ?? 0;
      } else {
        map[key] = double.tryParse(value) ?? 0.0;
      }
    }
    return map;
  }
}