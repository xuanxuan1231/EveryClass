import 'package:flutter/services.dart';

import '../services/schedule_service.dart';
import '../models/resolved_lesson.dart';

/// Dart 侧的实时通知桥接。
///
/// 原生实现见 Android `ScheduleForegroundService`（M3）/ iOS `LiveActivityManager`
/// （M4）。在未实现的平台（Linux 桌面、测试）上，调用会被静默忽略。
class LiveNotification {
  static const MethodChannel _channel =
      MethodChannel('everyclass/live_notification');

  /// 下发某天的课表并启动/更新常驻实时通知。
  ///
  /// 提醒开关（[remindBefore]/[remindStart]/[remindEnd] 与 [remindLeadSeconds]）
  /// 随课表一起下发：常驻通知的前台服务在课程边界弹出独立的一次性提醒。
  static Future<void> start(
    DaySchedule day, {
    bool enhancedCountdown = false,
    bool remindBefore = false,
    bool remindStart = false,
    bool remindEnd = false,
    int remindLeadSeconds = 300,
  }) async {
    await _safe('start', {
      'enhancedCountdown': enhancedCountdown,
      'remindBefore': remindBefore,
      'remindStart': remindStart,
      'remindEnd': remindEnd,
      'remindLeadSeconds': remindLeadSeconds,
      'lessons': day.lessons.map(_encode).toList(),
    });
  }

  /// 停止并移除实时通知。
  static Future<void> stop() async {
    await _safe('stop', null);
  }

  static Future<void> _safe(String method, Object? args) async {
    try {
      await _channel.invokeMethod(method, args);
    } on MissingPluginException {
      // 平台未实现——桌面/测试环境正常忽略。
    } on PlatformException {
      // 原生侧异常不应影响 UI。
    }
  }

  static Map<String, dynamic> _encode(ResolvedLesson l) => {
        'subject': l.subjectName,
        'room': l.room,
        'teacher': l.teacher,
        'period': l.period,
        // 距零点的毫秒——原生侧结合当天日期还原绝对时刻。
        'startMs': l.start.inMilliseconds,
        'endMs': l.end.inMilliseconds,
      };
}
