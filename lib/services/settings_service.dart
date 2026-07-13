import 'package:shared_preferences/shared_preferences.dart';

/// 应用设置：学期起始日（算轮换周）、实时倒计时与课程提醒选项。
class SettingsService {
  static const String _kTermStart = 'term_start';
  static const String _kEnhancedCountdown = 'enhanced_countdown';
  static const String _kRemindBefore = 'remind_before';
  static const String _kRemindStart = 'remind_start';
  static const String _kRemindEnd = 'remind_end';
  static const String _kRemindLeadMin = 'remind_lead_min';
  static const String _kRemindLeadSec = 'remind_lead_sec';

  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  static Future<SettingsService> create() async {
    return SettingsService(await SharedPreferences.getInstance());
  }

  DateTime? get termStart {
    final s = _prefs.getString(_kTermStart);
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<void> setTermStart(DateTime? day) async {
    if (day == null) {
      await _prefs.remove(_kTermStart);
    } else {
      await _prefs.setString(
        _kTermStart,
        DateTime(day.year, day.month, day.day).toIso8601String(),
      );
    }
  }

  /// 岛内计时：true=逐秒 M:SS（服务每秒重发，较耗电）；false=分钟数。默认关。
  bool get enhancedCountdown => _prefs.getBool(_kEnhancedCountdown) ?? false;

  Future<void> setEnhancedCountdown(bool value) =>
      _prefs.setBool(_kEnhancedCountdown, value);

  // ---- 课程提醒（一次性 heads-up，独立于常驻通知；依赖常驻通知运行）----

  /// 即将上课提醒（上课前 [remindLeadMinutes] 分钟）。默认关。
  bool get remindBefore => _prefs.getBool(_kRemindBefore) ?? false;

  Future<void> setRemindBefore(bool value) =>
      _prefs.setBool(_kRemindBefore, value);

  /// 上课提醒（到点）。默认关。
  bool get remindStart => _prefs.getBool(_kRemindStart) ?? false;

  Future<void> setRemindStart(bool value) =>
      _prefs.setBool(_kRemindStart, value);

  /// 下课提醒（到点）。默认关。
  bool get remindEnd => _prefs.getBool(_kRemindEnd) ?? false;

  Future<void> setRemindEnd(bool value) => _prefs.setBool(_kRemindEnd, value);

  /// 即将上课的提前量（秒，仅 [remindBefore] 使用）。30 秒粒度，范围 30–600，默认 300（5 分钟）。
  int get remindLeadSeconds {
    final stored = _prefs.getInt(_kRemindLeadSec) ??
        // 兼容旧版本以「分钟」存储的值。
        (_prefs.getInt(_kRemindLeadMin) ?? 5) * 60;
    return stored.clamp(30, 600).toInt();
  }

  Future<void> setRemindLeadSeconds(int seconds) =>
      _prefs.setInt(_kRemindLeadSec, seconds.clamp(30, 600).toInt());
}
