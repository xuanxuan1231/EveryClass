import 'package:flutter/services.dart';

/// 桌面卡片「点课」深链在 Dart 侧的入口（仅 Android 实现，见 MainActivity 的
/// `everyclass/deeplink` 通道）。其它平台调用会静默失败。
///
/// 卡片点课携带的课程身份：[subjectId]（课程 ID）+ [startMinute]（起始分钟数，
/// 距零点）。应用侧据此在当天已解析课表里定位这节课并唤出详情浮窗。
class PendingLesson {
  final String subjectId;
  final int startMinute;

  const PendingLesson({required this.subjectId, required this.startMinute});

  /// 从原生传来的松散 map 解析；字段缺失或类型不符返回 null。
  static PendingLesson? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final sid = raw['subjectId'];
    final start = raw['startMinute'];
    if (start is! int) return null;
    // subjectId 允许为空（旧快照/无 ID），此时只按 startMinute 定位。
    if ((sid is! String || sid.isEmpty) && start < 0) return null;
    return PendingLesson(
      subjectId: sid is String ? sid : '',
      startMinute: start,
    );
  }
}

class WidgetDeepLink {
  static const MethodChannel _channel = MethodChannel('everyclass/deeplink');

  /// 拉取「启动应用的那次点课」（冷启动路径）；没有则返回 null。
  static Future<PendingLesson?> initialLesson() async {
    try {
      final res = await _channel.invokeMethod<Object?>('getInitialLesson');
      return PendingLesson.fromMap(res);
    } on MissingPluginException {
      return null; // 非 Android 平台未实现
    } on PlatformException {
      return null;
    }
  }

  /// 注册「应用已在前台时又点了课」的回调（热启动路径，来自原生 onNewIntent）。
  static void setListener(void Function(PendingLesson) onOpen) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openLesson') {
        final p = PendingLesson.fromMap(call.arguments);
        if (p != null) onOpen(p);
      }
      return null;
    });
  }
}
