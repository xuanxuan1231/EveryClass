import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/resolved_lesson.dart';
import '../services/schedule_service.dart';
import '../ui/schedule/lesson_colors.dart';

/// 把「未来若干天已解析课表」导出成一份扁平 JSON，供 HarmonyOS 桌面服务卡片
/// 读取渲染。
///
/// 卡片跑在独立的 `FormExtensionAbility` 进程里、没有 Flutter 引擎，无法直接
/// 调用 Dart 排课引擎；因此这里在应用侧把课表预解析好写到应用文档目录
/// （鸿蒙上即 `filesDir`），卡片进程只需读这份扁平数据即可。
///
/// 只在鸿蒙上写文件，其它平台直接跳过，不影响原有行为。
class CardSnapshot {
  /// 与卡片侧（EntryFormAbility.ets）约定的文件名，改动需两侧同步。
  static const String fileName = 'card_snapshot.json';

  /// 快照落盘后请求原生立即刷新桌面卡片的通道（仅 Android 实现，见
  /// MainActivity 的 `refresh`）。其它平台未实现，静默忽略。
  static const MethodChannel _widgetChannel = MethodChannel('everyclass/widget');

  /// 导出的天数窗口：够覆盖到应用长时间不打开时的跨天翻页。
  static const int _days = 14;

  /// 依据当前选中课表的 [schedule] 生成快照并落盘；[schedule] 为空表示暂无
  /// 可用课表，会写出一份「无课程」的空快照，让卡片显示占位提示。
  ///
  /// 只有 HarmonyOS 上的桌面卡片会读这份文件；其它平台写一份没人读的小 JSON，
  /// 无副作用。之所以不按平台名过滤，是因为鸿蒙 Flutter 分支上 `Platform`
  /// 的取值不稳定，按平台名判断可能整段被跳过、导致卡片永远拿不到数据。
  static Future<void> export(
    ScheduleService? schedule, {
    String calendarName = '',
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final days = <Map<String, dynamic>>[];
      if (schedule != null) {
        for (var i = 0; i < _days; i++) {
          final day = today.add(Duration(days: i));
          final lessons = schedule.scheduleFor(day).lessons;
          days.add(<String, dynamic>{
            'date': _ymd(day),
            'weekday': day.weekday,
            'week': schedule.weekOf(day),
            'lessons': lessons.map(_lessonJson).toList(),
          });
        }
      }

      final payload = <String, dynamic>{
        'version': 1,
        'generatedAt': now.toIso8601String(),
        'calendarName': calendarName,
        'days': days,
      };
      await file.writeAsString(jsonEncode(payload));
      // 落盘完成后立即请求原生重绘桌面卡片——不必等回到桌面（onStop）或下一次
      // 前台服务分钟 tick，避免改动课程后卡片仍显示旧数据。必须在写文件之后调用，
      // 保证卡片进程读到的是新快照。
      await _requestWidgetRefresh();
    } catch (_) {
      // 导出失败不影响主流程（卡片会退回上一次快照或占位提示）。
    }
  }

  /// 通知原生侧「快照已更新，请立即刷新桌面卡片」。未实现该通道的平台
  /// （iOS / 桌面 / 测试）会抛 [MissingPluginException]，直接忽略。
  static Future<void> _requestWidgetRefresh() async {
    try {
      await _widgetChannel.invokeMethod<void>('refresh');
    } on MissingPluginException {
      // 平台未实现——正常忽略。
    } on PlatformException {
      // 原生侧异常不应影响主流程。
    }
  }

  static Map<String, dynamic> _lessonJson(ResolvedLesson l) => <String, dynamic>{
        // 课程 ID + 起始分钟数（距零点）：桌面卡片点课深链回应用时，用它俩在
        // 当天已解析课表里定位到这节课并唤出详情浮窗（见 widget_deeplink.dart）。
        'subjectId': l.subjectId,
        'name': l.subjectName,
        'room': l.room,
        'teacher': l.teacher,
        'start': _hhmm(l.start),
        'end': _hhmm(l.end),
        'startPeriod': l.startPeriod,
        'endPeriod': l.endPeriod,
        // 写「已解析的展示色」而非原始 l.color：无自选色时也带上应用内按课程稳定
        // 取的调色板色，桌面卡片色条才能与应用内课程颜色一致。
        'color': colorToHex(lessonColor(l)),
      };

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _hhmm(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}
