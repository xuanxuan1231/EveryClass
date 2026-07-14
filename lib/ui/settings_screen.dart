import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/classisland_importer.dart';
import '../platform/file_import.dart';
import '../platform/live_notification.dart';
import '../util/format.dart';
import 'schedule/calendar_edit_screen.dart';
import 'schedule/calendars_screen.dart';

/// 设置：课表管理与导入、实时通知与课程提醒、按科目填教室。
/// 学期开始日期在「课表管理」的课表编辑页设置。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cal = app.calendar;
    final courses = (cal?.courses.values.toList() ?? [])
      ..sort((a, b) => a.title.compareTo(b.title));

    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: false),
      body: ListView(
        children: [
          _sectionTitle(context, '课表'),
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('课表管理'),
            subtitle: Text(
              cal == null
                  ? '还没有课表 · 可新建或导入'
                  : '${app.calendars.length} 张课表 · 使用中：${calendarDisplayName(cal)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CalendarsScreen(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('导入 ClassIsland 档案'),
            subtitle: const Text('将档案转换为一张新课表，不影响已有课表'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showImportSheet(context, app),
          ),
          const Divider(height: 1),
          _sectionTitle(
            context,
            '实时通知',
            note: '在锁屏与状态栏常驻显示当前与下一节课',
          ),
          SwitchListTile(
            secondary: const Icon(Icons.timer_outlined),
            title: const Text('实时倒计时'),
            subtitle: const Text('逐秒跳动，更精确但更耗电'),
            value: app.settings.enhancedCountdown,
            onChanged: (v) => app.setEnhancedCountdown(v),
          ),
          if (kDebugMode) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('开发：预览实时活动'),
              subtitle: const Text('启动五分钟演示课程，用于检查锁屏和灵动岛显示'),
              onTap: () => _runLiveActivityDemo(context),
            ),
          ],
          const Divider(height: 1),
          _sectionTitle(context, '上课提醒'),
          SwitchListTile(
            secondary: const Icon(Icons.upcoming_outlined),
            title: const Text('即将上课'),
            subtitle: Text('课前 ${leadCn(app.settings.remindLeadSeconds)}'),
            value: app.settings.remindBefore,
            onChanged: (v) => app.setRemindBefore(v),
          ),
          _LeadTimeSlider(
            seconds: app.settings.remindLeadSeconds,
            enabled: app.settings.remindBefore,
            onChanged: (v) => app.setRemindLeadSeconds(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.play_circle_outline),
            title: const Text('上课'),
            subtitle: const Text('每节课开始时'),
            value: app.settings.remindStart,
            onChanged: (v) => app.setRemindStart(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.stop_circle_outlined),
            title: const Text('下课'),
            subtitle: const Text('每节课结束时'),
            value: app.settings.remindEnd,
            onChanged: (v) => app.setRemindEnd(v),
          ),
          const Divider(height: 1),
          _sectionTitle(context, '走班教室'),
          if (courses.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('导入档案后，可为每门课程填写走班教室。'),
            )
          else
            for (final c in courses)
              ListTile(
                dense: true,
                title: Text(c.title),
                subtitle: c.teacher.isEmpty ? null : Text(c.teacher),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      c.defaultLocation.isEmpty ? '未填' : c.defaultLocation,
                      style: TextStyle(
                        color: c.defaultLocation.isEmpty
                            ? Theme.of(context).colorScheme.outline
                            : Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit_outlined, size: 18),
                  ],
                ),
                onTap: () =>
                    _editRoom(context, app, c.id, c.title, c.defaultLocation),
              ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text, {String? note}) =>
      Padding(
        padding: EdgeInsets.fromLTRB(16, 20, 16, note == null ? 8 : 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  note,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ),
          ],
        ),
      );

  // ---- 导入 ----

  void _showImportSheet(BuildContext context, AppState app) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('选择 .json 文件'),
              onTap: () {
                Navigator.pop(sheetContext);
                _importFile(context, app);
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('粘贴 JSON 文本'),
              onTap: () {
                Navigator.pop(sheetContext);
                _importPaste(context, app);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importFile(BuildContext context, AppState app) async {
    final text = await FileImport.pickJsonText();
    if (text == null || text.trim().isEmpty) {
      if (context.mounted) {
        _snack(context, '未选择文件（或此平台不支持），可改用「粘贴 JSON 文本」。');
      }
      return;
    }
    if (context.mounted) await _doImport(context, app, text);
  }

  Future<void> _importPaste(BuildContext context, AppState app) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('粘贴档案 JSON'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: '{ "Subjects": { ... } }',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (text != null && text.trim().isNotEmpty && context.mounted) {
      await _doImport(context, app, text);
    }
  }

  Future<void> _doImport(BuildContext context, AppState app, String text) async {
    try {
      await app.importFromText(text);
      if (context.mounted) {
        _snack(
          context,
          '已导入为新课表：${app.calendar?.courses.length ?? 0} 门课程',
        );
      }
    } on ImportException catch (e) {
      if (context.mounted) _snack(context, '导入失败：${e.message}');
    }
  }

  // ---- 教室编辑 ----

  Future<void> _editRoom(
    BuildContext context,
    AppState app,
    String courseId,
    String courseTitle,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final room = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$courseTitle 的教室'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '如：实验楼 302',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (room != null) await app.setCourseRoom(courseId, room);
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _runLiveActivityDemo(BuildContext context) async {
    final started = await LiveNotification.runDemo();
    if (!context.mounted) return;
    _snack(
      context,
      started ? '已启动演示实时活动' : '当前设备不支持或未启用实时活动',
    );
  }
}

/// 「提前量」滑块：30 秒 – 10 分钟，30 秒粒度。
///
/// 拖动时只更新本地值（标签实时跟随），松手（[Slider.onChangeEnd]）才落库，
/// 避免每一帧都触发 [AppState] 刷新常驻通知。
class _LeadTimeSlider extends StatefulWidget {
  final int seconds;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const _LeadTimeSlider({
    required this.seconds,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_LeadTimeSlider> createState() => _LeadTimeSliderState();
}

class _LeadTimeSliderState extends State<_LeadTimeSlider> {
  static const double _min = 30; // 30 秒
  static const double _max = 600; // 10 分钟

  // 钳到 30–600 以满足 Slider 约束（兼容历史上超区间的旧值）。
  late double _value = widget.seconds.clamp(30, 600).toDouble();

  @override
  void didUpdateWidget(_LeadTimeSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 落库后新值回流时同步本地滑块。
    if (widget.seconds != oldWidget.seconds) {
      _value = widget.seconds.clamp(30, 600).toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueColor =
        widget.enabled ? theme.colorScheme.primary : theme.colorScheme.outline;
    return ListTile(
      enabled: widget.enabled,
      leading: const SizedBox(width: 24),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('提前量'),
          Text(
            leadCn(_value.round()),
            style: TextStyle(color: valueColor, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      subtitle: Slider(
        value: _value,
        min: _min,
        max: _max,
        divisions: 19, // 30 秒一档：(600 - 30) / 30
        label: leadCn(_value.round()),
        onChanged: widget.enabled ? (v) => setState(() => _value = v) : null,
        onChangeEnd: widget.enabled ? (v) => widget.onChanged(v.round()) : null,
      ),
    );
  }
}
