import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/classisland_importer.dart';
import '../platform/file_import.dart';
import '../util/format.dart';

/// 设置：导入档案、学期起始日、按科目填教室、实时通知开关。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final subjects = app.profile.subjects.entries.toList()
      ..sort((a, b) => a.value.name.compareTo(b.value.name));

    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: false),
      body: ListView(
        children: [
          _sectionTitle(context, '课表数据'),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('导入 ClassIsland 档案'),
            subtitle: Text(
              app.hasSchedule
                  ? '已导入：${app.profile.subjects.length} 门科目 · ${app.profile.classPlans.length} 张课表'
                  : app.profile.subjects.isNotEmpty
                      ? '已导入 ${app.profile.subjects.length} 门科目（暂无课表定义）'
                      : '未导入',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showImportSheet(context, app),
          ),
          const Divider(height: 1),
          _sectionTitle(context, '学期'),
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('学期开始日期'),
            subtitle: Text(
              app.settings.termStart == null
                  ? '未设置（不区分单双周）'
                  : '${ymd(app.settings.termStart!)}　·　用于计算轮换周',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickTermStart(context, app),
          ),
          const Divider(height: 1),
          _sectionTitle(context, '实时通知'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('启用实时通知'),
            subtitle: const Text('在锁屏/状态栏常驻显示当前与下一节课'),
            value: app.settings.notificationEnabled,
            onChanged: (v) => app.setNotificationEnabled(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.timer_outlined),
            title: const Text('实时倒计时'),
            subtitle: const Text('开：逐秒跳动（较耗电）；关：显示分钟数'),
            value: app.settings.enhancedCountdown,
            onChanged: app.settings.notificationEnabled
                ? (v) => app.setEnhancedCountdown(v)
                : null,
          ),
          const Divider(height: 1),
          _sectionTitle(context, '走班教室（按科目）'),
          if (subjects.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('导入档案后，可在此为每门科目填写走班教室。'),
            )
          else
            for (final e in subjects)
              ListTile(
                dense: true,
                title: Text(e.value.name),
                subtitle: e.value.teacherName.isEmpty
                    ? null
                    : Text(e.value.teacherName),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      e.value.defaultRoom.isEmpty ? '未填' : e.value.defaultRoom,
                      style: TextStyle(
                        color: e.value.defaultRoom.isEmpty
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
                    _editRoom(context, app, e.key, e.value.name, e.value.defaultRoom),
              ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
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
        _snack(context, '导入成功：${app.profile.subjects.length} 门科目');
      }
    } on ImportException catch (e) {
      if (context.mounted) _snack(context, '导入失败：${e.message}');
    }
  }

  // ---- 学期起始日 ----

  Future<void> _pickTermStart(BuildContext context, AppState app) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: app.settings.termStart ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '选择学期第一周内任意一天',
    );
    if (picked != null) await app.setTermStart(picked);
  }

  // ---- 教室编辑 ----

  Future<void> _editRoom(
    BuildContext context,
    AppState app,
    String subjectId,
    String subjectName,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final room = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$subjectName 的教室'),
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
    if (room != null) await app.setSubjectRoom(subjectId, room);
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}
