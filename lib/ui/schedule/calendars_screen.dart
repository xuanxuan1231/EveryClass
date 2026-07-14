import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/calendar.dart';
import '../../util/format.dart';
import 'calendar_edit_screen.dart';
import 'lesson_colors.dart';

/// 课表管理：列出设备上的全部课表，点按切换「使用中」，右侧编辑，右下角
/// 新建。日/周视图、课程管理与常驻通知始终跟随使用中的那张。
///
/// 删除入口在编辑页（与课程编辑一致）；导入 ClassIsland 档案会新增一张
/// 课表，入口在「设置」。
class CalendarsScreen extends StatelessWidget {
  const CalendarsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final calendars = app.calendars;
    final selectedId = app.calendar?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('课表管理'), centerTitle: false),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('新建课表'),
      ),
      body: calendars.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_month_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '还没有课表',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '点右下角「新建课表」创建，\n或到「设置」导入 ClassIsland 档案。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                for (final cal in calendars)
                  _CalendarTile(
                    calendar: cal,
                    selected: cal.id == selectedId,
                  ),
              ],
            ),
    );
  }

  static void _openEditor(BuildContext context, [Calendar? calendar]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CalendarEditScreen(calendar: calendar),
      ),
    );
  }
}

/// 一张课表：色点 + 名称 + 概要（开学日期 · 周数 · 课程数，另起一行备注）。
/// 点按选用；使用中的以选中态 + 对勾标识。
class _CalendarTile extends StatelessWidget {
  final Calendar calendar;
  final bool selected;

  const _CalendarTile({required this.calendar, required this.selected});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = parseHexColor(calendar.color);
    final info = [
      calendar.firstWeekStart == null
          ? '未设开始日期'
          : '${ymd(calendar.firstWeekStart!)} 开学',
      '${calendar.weekCount} 周',
      '${calendar.courses.length} 门课程',
    ].join(' · ');

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color ?? scheme.secondaryContainer,
        foregroundColor:
            color != null ? Colors.white : scheme.onSecondaryContainer,
        child: Icon(
          selected ? Icons.check : Icons.calendar_month_outlined,
          size: 20,
        ),
      ),
      title: Text(
        calendarDisplayName(calendar),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(info, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (calendar.note.isNotEmpty)
            Text(
              calendar.note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.outline),
            ),
        ],
      ),
      selected: selected,
      trailing: IconButton(
        tooltip: '编辑课表',
        icon: const Icon(Icons.edit_outlined),
        onPressed: () => CalendarsScreen._openEditor(context, calendar),
      ),
      onTap: () => context.read<AppState>().selectCalendar(calendar.id),
    );
  }
}
