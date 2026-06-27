import 'dart:convert';
import 'package:http/http.dart' as http;

const String _baseUrl = 'http://10.226.101.235:8000';

// ─── Day usage model ──────────────────────────────────────────────────────────

class DayUsage {
  final double screenTimeHours;
  final double appSwitchesPerHour;
  final double uniqueAppsPerDay;
  final double socialAppRatio;
  final double workAppRatio;
  final double entertainmentRatio;
  final double wellnessRatio;
  final double sleepHours;
  final double sleepQuality;
  final double exerciseMinPerWeek;
  final double socialHoursPerWeek;
  final double callCount;
  final double missedCallRatio;
  final double smsCount;

  const DayUsage({
    required this.screenTimeHours,
    required this.appSwitchesPerHour,
    required this.uniqueAppsPerDay,
    required this.socialAppRatio,
    required this.workAppRatio,
    required this.entertainmentRatio,
    required this.wellnessRatio,
    required this.sleepHours,
    required this.sleepQuality,
    required this.exerciseMinPerWeek,
    required this.socialHoursPerWeek,
    required this.callCount,
    required this.missedCallRatio,
    required this.smsCount,
  });

  Map<String, dynamic> toJson() => {
        'screen_time_hours':     screenTimeHours,
        'app_switches_per_hour': appSwitchesPerHour,
        'unique_apps_per_day':   uniqueAppsPerDay,
        'social_app_ratio':      socialAppRatio,
        'work_app_ratio':        workAppRatio,
        'entertainment_ratio':   entertainmentRatio,
        'wellness_ratio':        wellnessRatio,
        'sleep_hours':           sleepHours,
        'sleep_quality':         sleepQuality,
        'exercise_min_per_week': exerciseMinPerWeek,
        'social_hours_per_week': socialHoursPerWeek,
        'call_count':            callCount,
        'missed_call_ratio':     missedCallRatio,
        'sms_count':             smsCount,
      };
}

// ─── Results ──────────────────────────────────────────────────────────────────

class BurnoutResult {
  final double score;      // 1–10
  final String level;      // "Low 🟢" / "Moderate 🟠" / "High 🔴"
  final String source;     // "Manual" / "LSTM"
  final Map<String, double>? personalBaseline;
  final Map<String, double>? todayVsBaseline;

  const BurnoutResult({
    required this.score,
    required this.level,
    required this.source,
    this.personalBaseline,
    this.todayVsBaseline,
  });
}

// ─── API Service ──────────────────────────────────────────────────────────────

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  // ── Manual PyTorch /predict — 1–10 scale ─────────────────────────────────
  Future<BurnoutResult> predictManual(DayUsage day) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl/predict'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'sleep_hours':           day.sleepHours,
            'sleep_quality':         day.sleepQuality,
            'app_switches_per_hour': day.appSwitchesPerHour,
            'social_app_ratio':      day.socialAppRatio,
            'productivity_ratio':    day.workAppRatio,
            'unique_apps_per_day':   day.uniqueAppsPerDay,
            'call_count':            day.callCount,
            'total_call_min':        day.callCount * 5.0,
            'missed_call_ratio':     day.missedCallRatio,
            'sms_count':             day.smsCount,
            'sms_sent_ratio':        0.5,
            'screen_time_hours':     day.screenTimeHours,
            'exercise_min_per_week': day.exerciseMinPerWeek,
            'social_hours_per_week': day.socialHoursPerWeek,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return BurnoutResult(
        score:  double.parse(data['prediction'].toString()),
        level:  data['stress_level'].toString(),
        source: 'Manual',
      );
    }
    throw Exception('/predict error ${response.statusCode}: ${response.body}');
  }

  // ── LSTM /predict_lstm — personalised 7-day baseline + today ─────────────
  // pastDays: list of 7 DayUsage (oldest first, index 0 = 7 days ago)
  // today:    today's DayUsage
  Future<BurnoutResult> predictLSTM({
    required List<DayUsage> pastDays,
    required DayUsage today,
  }) async {
    if (pastDays.length != 7) {
      throw Exception('predictLSTM needs exactly 7 past days, got ${pastDays.length}');
    }

    final response = await http
        .post(
          Uri.parse('$_baseUrl/predict_lstm'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'history': pastDays.map((d) => d.toJson()).toList(),
            'today':     today.toJson(),
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      // Parse personal baseline
      final pb = (data['user_baseline'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, double.parse(v.toString())));

      // Parse today vs baseline
      final tvb = (data['today_vs_baseline'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, double.parse(v.toString())));

      return BurnoutResult(
        score:            double.parse(data['prediction'].toString()),
        level:            data['stress_level'].toString(),
        source:           'LSTM',
        personalBaseline: pb,
        todayVsBaseline:  tvb,
      );
    }
    throw Exception('/predict_lstm error ${response.statusCode}: ${response.body}');
  }
}
