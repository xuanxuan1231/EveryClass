import 'package:flutter/services.dart';

import '../services/schedule_service.dart';
import '../models/resolved_lesson.dart';

/// Dart 侧的实时通知桥接。
///
/// 原生实现见 Android `ScheduleForegroundService`（M3）/ iOS `LiveActivityManager`
/// （M4）。在未实现的平台（Linux 桌面、测试）上，调用会被静默忽略。
class LiveNotification {
  static const MethodChannel _channel = MethodChannel(
    'everyclass/live_notification',
  );

  /// 下发某天的课表并启动/更新常驻实时通知。
  static Future<bool> isSupported() => _safe('isSupported', null);

  static Future<bool> start(DaySchedule day, {bool enhancedCountdown = false}) {
    return _safe('start', {
      'enhancedCountdown': enhancedCountdown,
      'lessons': day.lessons.map(_encode).toList(),
    });
  }

  static Future<bool> update(LiveNotificationState state) {
    return _safe('update', state.toMap());
  }

  /// 停止并移除实时通知。
  static Future<bool> stop() => _safe('stop', null);

  static Future<bool> runDemo({DateTime? now}) {
    final start = now ?? DateTime.now();
    return update(
      LiveNotificationState(
        subject: '演示课程',
        room: 'A101',
        teacher: 'EveryClass',
        phase: '上课中',
        statusLabel: '距下课',
        countdownStart: start,
        countdownEnd: start.add(const Duration(minutes: 5)),
      ),
    );
  }

  static Future<bool> _safe(String method, Object? args) async {
    try {
      final result = await _channel.invokeMethod<Object?>(method, args);
      return result == true;
    } on MissingPluginException {
      // 平台未实现——桌面/测试环境正常忽略。
      return false;
    } on PlatformException {
      // 原生侧异常不应影响 UI。
      return false;
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

class LiveNotificationState {
  final String subject;
  final String room;
  final String teacher;
  final String phase;
  final String statusLabel;
  final DateTime countdownStart;
  final DateTime countdownEnd;

  const LiveNotificationState({
    required this.subject,
    required this.room,
    required this.teacher,
    required this.phase,
    required this.statusLabel,
    required this.countdownStart,
    required this.countdownEnd,
  });

  Map<String, Object> toMap() => {
    'subject': subject,
    'room': room,
    'teacher': teacher,
    'phase': phase,
    'statusLabel': statusLabel,
    'countdownStartEpochMs': countdownStart.millisecondsSinceEpoch,
    'countdownEndEpochMs': countdownEnd.millisecondsSinceEpoch,
  };
}
