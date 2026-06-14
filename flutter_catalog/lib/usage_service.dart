import 'package:flutter/services.dart';

// ─── Single day raw data ──────────────────────────────────────────────────────

class DayUsageRaw {
  final int    daysAgo;
  final String dateLabel;        // e.g. "12/6"
  final double screenTimeHours;
  final int    appSwitchesPerHour;  // whole number
  final int    totalAppSwitches;    // raw count for the day
  final int    uniqueAppsPerDay;
  final double socialAppRatio;
  final double workAppRatio;
  final double entertainmentRatio;
  final double wellnessRatio;

  const DayUsageRaw({
    required this.daysAgo,
    required this.dateLabel,
    required this.screenTimeHours,
    required this.appSwitchesPerHour,
    required this.totalAppSwitches,
    required this.uniqueAppsPerDay,
    required this.socialAppRatio,
    required this.workAppRatio,
    required this.entertainmentRatio,
    required this.wellnessRatio,
  });

  factory DayUsageRaw.fromMap(Map map) => DayUsageRaw(
        daysAgo:            (map['daysAgo']            as num).toInt(),
        dateLabel:           map['dateLabel']?.toString() ?? '',
        screenTimeHours:    (map['screenTimeHours']    as num).toDouble(),
        appSwitchesPerHour: (map['appSwitchesPerHour'] as num).toInt(),
        totalAppSwitches:   (map['totalAppSwitches']   as num).toInt(),
        uniqueAppsPerDay:   (map['uniqueAppsPerDay']   as num).toInt(),
        socialAppRatio:     (map['socialAppRatio']     as num).toDouble(),
        workAppRatio:       (map['workAppRatio']       as num).toDouble(),
        entertainmentRatio: (map['entertainmentRatio'] as num).toDouble(),
        wellnessRatio:      (map['wellnessRatio']      as num).toDouble(),
      );

  bool get hasData => screenTimeHours > 0.05;
}

// ─── Personal baseline + dynamic thresholds ───────────────────────────────────

class PersonalBaseline {
  final double avgScreenTime;
  final double avgSocialRatio;
  final double avgWorkRatio;
  final int    avgAppSwitchesPerHour;  // whole number
  final double stdScreenTime;
  final double stdSocialRatio;
  final int    stdAppSwitches;

  // Dynamic thresholds — computed from THIS user's real history
  final double thresholdScreenTime;
  final double thresholdSocialRatio;
  final int    thresholdAppSwitches;   // whole number

  final int    daysOfData;

  const PersonalBaseline({
    required this.avgScreenTime,
    required this.avgSocialRatio,
    required this.avgWorkRatio,
    required this.avgAppSwitchesPerHour,
    required this.stdScreenTime,
    required this.stdSocialRatio,
    required this.stdAppSwitches,
    required this.thresholdScreenTime,
    required this.thresholdSocialRatio,
    required this.thresholdAppSwitches,
    required this.daysOfData,
  });

  double screenZScore(double v) =>
      stdScreenTime > 0 ? (v - avgScreenTime) / stdScreenTime : 0;
  double socialZScore(double v) =>
      stdSocialRatio > 0 ? (v - avgSocialRatio) / stdSocialRatio : 0;

  String get qualityLabel {
    if (daysOfData >= 7)  return 'Good  ($daysOfData days)';
    if (daysOfData >= 3)  return 'Building…  ($daysOfData days)';
    return 'Early  ($daysOfData days — use app more for accuracy)';
  }
}

// ─── Service ──────────────────────────────────────────────────────────────────

class UsageService {
  UsageService._();
  static final UsageService instance = UsageService._();

  static const _ch = MethodChannel('brainlag/usage_access');

  List<DayUsageRaw>? _history;
  PersonalBaseline?  _baseline;
  DateTime?          _lastFetch;
  DateTime?          _installDate;
  double?            _liveScreenTime;

  // ── Permission ───────────────────────────────────────────────────────────

  Future<bool> hasPermission() async {
    try {
      return await _ch.invokeMethod<bool>('checkUsageAccessPermission') ?? false;
    } catch (_) { return false; }
  }

  Future<void> openSettings() async =>
      _ch.invokeMethod('openUsageAccessSettings');

  // ── Install date ─────────────────────────────────────────────────────────

  Future<DateTime> getInstallDate() async {
    if (_installDate != null) return _installDate!;
    final ms = await _ch.invokeMethod<int>('getInstallDate') ??
        DateTime.now().millisecondsSinceEpoch;
    _installDate = DateTime.fromMillisecondsSinceEpoch(ms);
    return _installDate!;
  }

  int get daysSinceInstall =>
      _installDate == null
          ? 0
          : DateTime.now().difference(_installDate!).inDays + 1;

  // ── Live screen time ─────────────────────────────────────────────────────

  Future<double> fetchLiveScreenTime() async {
    try {
      final h = await _ch.invokeMethod<double>('getTodayScreenTime') ?? 0.0;
      _liveScreenTime = h;
      return h;
    } catch (_) {
      return _liveScreenTime ?? 0.0;
    }
  }

  double? get liveScreenTime => _liveScreenTime;

  // ── Fetch 7-day history from Digital Wellbeing ───────────────────────────
  // Always reads last 7 days regardless of install date
  // so the baseline is meaningful from day 1

  Future<List<DayUsageRaw>> fetchHistory({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _history != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!).inMinutes < 30) {
      return _history!;
    }

    await getInstallDate();

    // Always fetch 7 days — Digital Wellbeing has this data even before install
    final raw = await _ch.invokeMethod<List>(
        'getHistoricalUsage', {'days': 7});

    final all = raw!.map((e) => DayUsageRaw.fromMap(e as Map)).toList();

    // Keep all days — even zero screen time days are valid data points
    _history   = all;
    _lastFetch = DateTime.now();
    _baseline  = _buildBaseline(_history!);

    return _history!;
  }

  PersonalBaseline?  get baseline => _baseline;
  List<DayUsageRaw>? get history  => _history;

  // ── Build personal baseline from 7 days ──────────────────────────────────

  PersonalBaseline _buildBaseline(List<DayUsageRaw> all) {
    // Use all 7 days including today for baseline
    // (more data = better baseline)
    final valid = all
    .where((d) => d.daysAgo != 0)
    .where((d) => d.screenTimeHours > 0.05)
    .toList();

    if (valid.isEmpty) {
      return const PersonalBaseline(
        avgScreenTime: 5.0, avgSocialRatio: 0.30,
        avgWorkRatio: 0.40, avgAppSwitchesPerHour: 20,
        stdScreenTime: 1.5, stdSocialRatio: 0.10, stdAppSwitches: 8,
        thresholdScreenTime: 7.0, thresholdSocialRatio: 0.50,
        thresholdAppSwitches: 35, daysOfData: 0,
      );
    }

    // ── Averages ─────────────────────────────────────────────────────────────
    double avg(List<double> v) => v.reduce((a,b)=>a+b) / v.length;
    int    avgInt(List<int> v)  => (v.reduce((a,b)=>a+b) / v.length).round();

    double stdDev(List<double> v) {
      if (v.length < 2) return 0.1;
      final m = avg(v);
      final variance = v.map((x)=>(x-m)*(x-m)).reduce((a,b)=>a+b) / v.length;
      if (variance <= 0) return 0.01;
      double x = variance;
      for (int i = 0; i < 30; i++) x = (x + variance/x) / 2;
      return x < 0.01 ? 0.01 : x;
    }

    int stdDevInt(List<int> v) {
      if (v.length < 2) return 1;
      final m = v.reduce((a,b)=>a+b) / v.length;
      final variance = v.map((x)=>(x-m)*(x-m)).reduce((a,b)=>a+b) / v.length;
      if (variance <= 0) return 1;
      double x = variance;
      for (int i = 0; i < 30; i++) x = (x + variance/x) / 2;
      return x.round().clamp(1, 999);
    }

    // ── Dynamic threshold ─────────────────────────────────────────────────────
    // < 3 days  → mean + 1σ   (lenient)
    // 3–6 days  → 75th percentile
    // 7+ days   → 80th percentile (strict, most personalised)

    double thresh(List<double> vals, double mean, double std) {
      final s = List<double>.from(vals)..sort();
      final n = s.length;
      if (n < 3)  return mean + std;
      if (n < 7)  return s[((n-1)*0.75).round().clamp(0,n-1)];
      return s[((n-1)*0.80).round().clamp(0,n-1)];
    }

    int threshInt(List<int> vals, int mean, int std) {
      final s = List<int>.from(vals)..sort();
      final n = s.length;
      if (n < 3)  return mean + std;
      if (n < 7)  return s[((n-1)*0.75).round().clamp(0,n-1)];
      return s[((n-1)*0.80).round().clamp(0,n-1)];
    }

    final screens  = valid.map((d) => d.screenTimeHours).toList();
    final socials  = valid.map((d) => d.socialAppRatio).toList();
    final works    = valid.map((d) => d.workAppRatio).toList();
    final switches = valid.map((d) => d.appSwitchesPerHour).toList();

    final avgSc  = avg(screens);
    final avgSo  = avg(socials);
    final stdSc  = stdDev(screens);
    final stdSo  = stdDev(socials);
    final avgSw  = avgInt(switches);
    final stdSw  = stdDevInt(switches);

    return PersonalBaseline(
      avgScreenTime:       avgSc,
      avgSocialRatio:      avgSo,
      avgWorkRatio:        avg(works),
      avgAppSwitchesPerHour: avgSw,
      stdScreenTime:       stdSc,
      stdSocialRatio:      stdSo,
      stdAppSwitches:      stdSw,
      thresholdScreenTime:  thresh(screens,  avgSc, stdSc),
      thresholdSocialRatio: thresh(socials,  avgSo, stdSo),
      thresholdAppSwitches: threshInt(switches, avgSw, stdSw),
      daysOfData:          valid.length,
    );
  }
}