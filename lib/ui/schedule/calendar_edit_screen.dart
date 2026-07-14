import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/calendar.dart';
import '../../util/dates.dart';
import '../../util/format.dart';
import 'color_swatch_row.dart';

/// 课表显示名：未命名时兜底。
String calendarDisplayName(Calendar cal) =>
    cal.name.isEmpty ? '未命名课表' : cal.name;

/// 删除课表前的确认对话框；返回用户是否确认。
Future<bool> confirmDeleteCalendar(BuildContext context, String name) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: const Text('删除课表'),
        content: Text('将删除「$name」及其全部课程、排课与单次调整，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      );
    },
  );
  return ok == true;
}

/// 课表编辑页：新建（[calendar] 为 null）或编辑一张课表的基本信息——名称、
/// 颜色（可选）、学期开始日期、备注（可选）。周数由课程排课自动推导
/// （[Calendar.weekCount]），只读展示。保存走 [AppState.createCalendar] /
/// [AppState.updateCalendarInfo]；新建的课表自带默认作息并被选中。
class CalendarEditScreen extends StatefulWidget {
  final Calendar? calendar;

  const CalendarEditScreen({super.key, this.calendar});

  @override
  State<CalendarEditScreen> createState() => _CalendarEditScreenState();
}

class _CalendarEditScreenState extends State<CalendarEditScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.calendar?.name ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.calendar?.note ?? '');
  late String _color = widget.calendar?.color ?? '';
  late DateTime? _firstWeekStart = widget.calendar?.firstWeekStart;

  bool _nameError = false;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final weekCount = widget.calendar?.weekCount ?? Calendar.defaultWeekCount;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.calendar == null ? '新建课表' : '编辑课表'),
        centerTitle: false,
        actions: [
          if (widget.calendar != null)
            IconButton(
              tooltip: '删除课表',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(onPressed: _save, child: const Text('保存')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            controller: _name,
            autofocus: widget.calendar == null,
            decoration: InputDecoration(
              labelText: '课表名称',
              hintText: '如：2026 春季学期',
              border: const OutlineInputBorder(),
              errorText: _nameError ? '请填写课表名称' : null,
            ),
            onChanged: (_) {
              if (_nameError) setState(() => _nameError = false);
            },
          ),
          _sectionLabel(context, '颜色'),
          ColorSwatchRow(
            value: _color,
            emptyLabel: '默认',
            onChanged: (v) => setState(() => _color = v),
          ),
          _sectionLabel(context, '学期'),
          InkWell(
            onTap: _pickFirstWeekStart,
            borderRadius: BorderRadius.circular(4),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: '开始日期',
                helperText: '学期第一周所在日期，用于推断周次与轮换',
                border: const OutlineInputBorder(),
                suffixIcon: _firstWeekStart == null
                    ? const Icon(Icons.calendar_today_outlined)
                    : IconButton(
                        tooltip: '清除开始日期',
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            setState(() => _firstWeekStart = null),
                      ),
              ),
              child: Text(
                _firstWeekStart == null ? '未设置' : ymd(_firstWeekStart!),
                style: _firstWeekStart == null
                    ? TextStyle(color: scheme.outline)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: '周数',
              helperText: '按课程排课的周次自动计算，不可手动修改',
              border: OutlineInputBorder(),
              enabled: false,
              suffixIcon: Icon(Icons.lock_outline, size: 18),
            ),
            child: Text('$weekCount 周'),
          ),
          _sectionLabel(context, '备注'),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '如：大二下学期',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
        ),
      );

  Future<void> _pickFirstWeekStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _firstWeekStart ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '选择学期第一周内任意一天',
    );
    if (picked != null) setState(() => _firstWeekStart = dateOnly(picked));
  }

  // ---- 保存 / 删除 ----

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = true);
      return;
    }
    final app = context.read<AppState>();
    final existing = widget.calendar;
    if (existing == null) {
      await app.createCalendar(
        name: name,
        color: _color,
        firstWeekStart: _firstWeekStart,
        note: _note.text.trim(),
      );
    } else {
      await app.updateCalendarInfo(
        existing.id,
        name: name,
        color: _color,
        firstWeekStart: _firstWeekStart,
        clearFirstWeekStart: _firstWeekStart == null,
        note: _note.text.trim(),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = widget.calendar;
    if (existing == null) return;
    final app = context.read<AppState>();
    final navigator = Navigator.of(context);
    if (!await confirmDeleteCalendar(context, calendarDisplayName(existing))) {
      return;
    }
    await app.deleteCalendar(existing.id);
    navigator.pop();
  }
}
