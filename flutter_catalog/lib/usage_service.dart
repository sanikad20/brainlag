import 'package:flutter/services.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class DayUsageRaw {
  final int    daysAgo;
  final double screenTimeHours;
  final double appSwitchesPerHour;
  final int    uniqueAppsPerDay;
  final double socialAppRatio;
  final double workAppRatio;
  final double entertainmentRatio;
  final double wellnessRatio;

  const DayUsageRaw({
    required this.daysAgo,
    required this.screenTimeHours,
    required this.appSwitchesPerHour,
    required this.uniqueAppsPerDay,
    required this.socialAppRatio,
    required this.workAppRatio,
    required this.entertainmentRatio,
    required this.wellnessRatio,
  });

  factory DayUsageRaw.fromMap(Map map) => DayUsageRaw(
        daysAgo:            (map['daysAgo']            as num).toInt(),
        screenTimeHours:    (map['screenTimeHours']    as num).toDouble(),
        appSwitchesPerHour: (map['appSwitchesPerHour'] as num).toDouble(),
        uniqueAppsPerDay:   (map['uniqueAppsPerDay']   as num).toInt(),
        socialAppRatio:     (map['socialAppRatio']     as num).toDouble(),
        workAppRatio:       (map['workAppRatio']       as num).toDouble(),
        entertainmentRatio: (map['entertainmentRatio'] as num).toDouble(),
        wellnessRatio:      (map['wellnessRatio']      as num).toDouble(),
      );
}

// ─── Personal Baseline ────────────────────────────────────────────────────────

class PersonalBaseline {
  final double avgScreenTime;
  final double avgAppSwitches;
  final double avgSocialRatio;
  final double avgWorkRatio;
  final double stdScreenTime;
  final double stdAppSwitches;
  final double stdSocialRatio;

  // Dynamic thresholds computed from user's own data
  final double thresholdScreenTime;
  final double thresholdSocialRatio;
  final double thresholdAppSwitches;

  // How many days of data we have
  final int daysOfData;

  const PersonalBaseline({
    required this.avgScreenTime,
    required this.avgAppSwitches,
    required this.avgSocialRatio,
    required this.avgWorkRatio,
    required this.stdScreenTime,
    required this.stdAppSwitches,
    required this.stdSocialRatio,
    required this.thresholdScreenTime,
    required this.thresholdSocialRatio,
    required this.thresholdAppSwitches,
    required this.daysOfData,
  });

  double screenZScore(double v) =>
      stdScreenTime  > 0 ? (v - avgScreenTime)  / stdScreenTime  : 0;
  double switchZScore(double v) =>
      stdAppSwitches > 0 ? (v - avgAppSwitches) / stdAppSwitches : 0;
  double socialZScore(double v) =>
      stdSocialRatio > 0 ? (v - avgSocialRatio) / stdSocialRatio : 0;

  String get dataQuality {
    if (daysOfData >= 10) return 'Good  ($daysOfData days)';
    if (daysOfData >= 5)  return 'Building…  ($daysOfData days)';
    return 'Early  ($daysOfData days — use app more for accuracy)';
  }

  @override
  String toString() =>
      'Baseline ($daysOfData days) — '
      'screen: ${avgScreenTime.toStringAsFixed(1)}h | '
      'social: ${(avgSocialRatio * 100).toStringAsFixed(0)}% | '
      'work: ${(avgWorkRatio * 100).toStringAsFixed(0)}%';
}

// ─── Usage Service ────────────────────────────────────────────────────────────

class UsageService {
  UsageService._();
  static final UsageService instance = UsageService._();

  static const _channel = MethodChannel('brainlag/usage_access');

  List<DayUsageRaw>? _history;
  PersonalBaseline?  _baseline;
  DateTime?          _lastFetch;
  DateTime?          _installDate;
  double?            _todayScreenTime;

  // ── Permission ───────────────────────────────────────────────────────────

  Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod<bool>(
              'checkUsageAccessPermission') ?? false;
    } catch (_) { return false; }
  }

  Future<void> openSettings() async {
    await _channel.invokeMethod('openUsageAccessSettings');
  }

  // ── Install date ─────────────────────────────────────────────────────────

  Future<DateTime> getInstallDate() async {
    if (_installDate != null) return _installDate!;
    final ms = await _channel.invokeMethod<int>('getInstallDate') ??
        DateTime.now().millisecondsSinceEpoch;
    _installDate = DateTime.fromMillisecondsSinceEpoch(ms);
    return _installDate!;
  }

  int get daysSinceInstall {
    if (_installDate == null) return 0;
    return DateTime.now().difference(_installDate!).inDays + 1;
  }

  // ── Today's live screen time ─────────────────────────────────────────────

  Future<double> fetchTodayScreenTime() async {
    try {
      final h = await _channel.invokeMethod<double>('getTodayScreenTime') ?? 0.0;
      _todayScreenTime = h;
      return h;
    } catch (_) {
      return _todayScreenTime ?? 0.0;
    }
  }

  double? get todayScreenTime => _todayScreenTime;

  // ── Fetch history ─────────────────────────────────────────────────────────
  // Only fetches days since install date

  Future<List<DayUsageRaw>> fetchHistory({
    int maxDays = 14,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _history != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!).inMinutes < 30) {
      return _history!;
    }

    // Get install date first
    await getInstallDate();

    final raw = await _channel.invokeMethod<List>(
        'getHistoricalUsage', {'days': maxDays});

    _history   = raw!.map((e) => DayUsageRaw.fromMap(e as Map)).toList();
    _lastFetch = DateTime.now();

    // Filter out days with no data (before install or unused days)
    _history = _history!
        .where((d) => d.screenTimeHours > 0.05)
        .toList();

    // Compute dynamic baseline + thresholds from real data
    _baseline = _computeBaseline(_history!);

    return _history!;
  }

  // ── Cached getters ───────────────────────────────────────────────────────

  PersonalBaseline?  get baseline => _baseline;
  List<DayUsageRaw>? get history  => _history;

  // ── Compute baseline + DYNAMIC thresholds from user's own data ────────────

  PersonalBaseline _computeBaseline(List<DayUsageRaw> history) {
    // Exclude today from baseline computation
    final base = history.where((d) => d.daysAgo > 0).toList();

    if (base.isEmpty) {
      return PersonalBaseline(
        avgScreenTime: 5.0, avgAppSwitches: 20.0,
        avgSocialRatio: 0.3, avgWorkRatio: 0.4,
        stdScreenTime: 1.5, stdAppSwitches: 8.0, stdSocialRatio: 0.1,
        thresholdScreenTime: 7.0,
        thresholdSocialRatio: 0.5,
        thresholdAppSwitches: 35.0,
        daysOfData: 0,
      );
    }

    // ── Math helpers ─────────────────────────────────────────────────────────
    double mean(List<double> v) =>
        v.reduce((a, b) => a + b) / v.length;

    double stdDev(List<double> v) {
      if (v.length < 2) return 0.1;
      final m = mean(v);
      final variance =
          v.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / v.length;
      if (variance <= 0) return 0.01;
      double x = variance;
      for (int i = 0; i < 30; i++) x = (x + variance / x) / 2;
      return x < 0.01 ? 0.01 : x;
    }

    // ── Dynamic threshold ─────────────────────────────────────────────────────
    // Uses percentile based on how much data we have:
    //  < 5 days  → mean + 1.0σ  (gentle threshold)
    //  5–9 days  → 75th percentile
    //  ≥10 days  → 80th percentile (stricter, more personalized)
    double dynamicThreshold(List<double> vals, double avg, double std) {
      final sorted = List<double>.from(vals)..sort();
      final n      = sorted.length;

      if (n < 5) {
        // Not enough data — use mean + 1σ
        return (avg + std).clamp(0.0, double.infinity);
      } else if (n < 10) {
        // 75th percentile
        final idx = ((n - 1) * 0.75).round().clamp(0, n - 1);
        return sorted[idx];
      } else {
        // 80th percentile — stricter
        final idx = ((n - 1) * 0.80).round().clamp(0, n - 1);
        return sorted[idx];
      }
    }

    final screens  = base.map((d) => d.screenTimeHours).toList();
    final switches = base.map((d) => d.appSwitchesPerHour).toList();
    final socials  = base.map((d) => d.socialAppRatio).toList();
    final works    = base.map((d) => d.workAppRatio).toList();

    final avgScreen  = mean(screens);
    final avgSwitch  = mean(switches);
    final avgSocial  = mean(socials);
    final stdScreen  = stdDev(screens);
    final stdSwitch  = stdDev(switches);
    final stdSocial  = stdDev(socials);

    return PersonalBaseline(
      avgScreenTime:  avgScreen,
      avgAppSwitches: avgSwitch,
      avgSocialRatio: avgSocial,
      avgWorkRatio:   mean(works),
      stdScreenTime:  stdScreen,
      stdAppSwitches: stdSwitch,
      stdSocialRatio: stdSocial,
      // Dynamic thresholds — computed from THIS user's actual history
      thresholdScreenTime:  dynamicThreshold(screens, avgScreen, stdScreen),
      thresholdSocialRatio: dynamicThreshold(socials, avgSocial, stdSocial),
      thresholdAppSwitches: dynamicThreshold(switches, avgSwitch, stdSwitch),
      daysOfData: base.length,
    );
  }
}