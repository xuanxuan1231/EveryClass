import 'package:shared_preferences/shared_preferences.dart';

/// 应用设置：学期起始日（算轮换周）与实时通知开关。
class SettingsService {
  static const String _kTermStart = 'term_start';
  static const String _kNotifEnabled = 'notif_enabled';
  static const String _kEnhancedCountdown = 'enhanced_countdown';

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

  bool get notificationEnabled => _prefs.getBool(_kNotifEnabled) ?? false;

  Future<void> setNotificationEnabled(bool value) =>
      _prefs.setBool(_kNotifEnabled, value);

  /// 岛内计时：true=逐秒 M:SS（服务每秒重发，较耗电）；false=分钟数。默认关。
  bool get enhancedCountdown => _prefs.getBool(_kEnhancedCountdown) ?? false;

  Future<void> setEnhancedCountdown(bool value) =>
      _prefs.setBool(_kEnhancedCountdown, value);
}
