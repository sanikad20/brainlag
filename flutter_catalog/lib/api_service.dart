import 'dart:convert';
import 'package:http/http.dart' as http;

const String _baseUrl = 'http://10.134.113.235:8000';

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

class BurnoutResult {
  final double score;
  final String level;
  const BurnoutResult({required this.score, required this.level});
}

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  Future<BurnoutResult> predictTwoDay({
    required DayUsage day1,
    required DayUsage day2,
  }) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl/predict_lstm'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'day1': day1.toJson(), 'day2': day2.toJson()}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return BurnoutResult(
        score: double.parse(data['prediction'].toString()),
        level: data['stress_level'].toString(),
      );
    } else {
      throw Exception('API error ${response.statusCode}: ${response.body}');
    }
  }
}