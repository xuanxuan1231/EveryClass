import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/alert.dart';
import '../../models/calendar.dart';
import '../../models/course_event.dart';
import '../../models/meeting.dart';
import '../../models/week_rule.dart';
import '../../util/format.dart';
import '../../util/local_id.dart';
import '../../util/week_set.dart';
import 'color_swatch_row.dart';
import 'course_icons.dart';
import 'lesson_colors.dart';
import 'time_fields.dart';

/// 时段的时间摘要：「第 1-2 节」或自定义时刻「19:00 - 20:30」。
String meetingTimeLabel(Meeting m) {
  if (m.usesCustomTime) return '${m.customStart} - ${m.customEnd}';
  return m.endPeriod > m.startPeriod
      ? '第 ${m.startPeriod}-${m.endPeriod} 节'
      : '第 ${m.startPeriod} 节';
}

/// 提醒的摘要：「上课前 5 分钟」「下课时」等（编辑页与单次编辑页共用）。
String alertLabel(Alert a) {
  final anchor = a.relativeToEnd ? '下课' : '上课';
  final secs = a.offset.inSeconds;
  if (secs == 0) return '$anchor时';
  return secs < 0 ? '$anchor前 ${leadCn(-secs)}' : '$anchor后 ${leadCn(secs)}';
}

/// 删除课程前的确认对话框；返回用户是否确认。
Future<bool> confirmDeleteCourse(BuildContext context, String title) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: const Text('删除课程'),
        content: Text('将删除「$title」及其全部排课时段与单次调整，无法恢复。'),
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

/// 课程编辑页（全局编辑）：新增（[course] 为 null）或编辑一门课程的全部信息
/// ——名称、颜色、图标、教师、默认教室、标签、备注、提醒，以及排课时段
/// （星期、节次或自定义时刻、周次规则、地点/教师覆盖）。保存整体写回
/// [AppState.upsertCourse]；已有时段上的单次调整（overrides）原样保留。
///
/// 只改某一次课（本次备注/教师/教室、调课、停课）走单次编辑页
/// `OccurrenceEditScreen`。
class CourseEditScreen extends StatefulWidget {
  final CourseEvent? course;

  /// 新增排课时段时默认选中的星期（1–7；如从日视图某天进入）。
  final int? initialWeekday;

  const CourseEditScreen({
    super.key,
    this.course,
    this.initialWeekday,
  });

  @override
  State<CourseEditScreen> createState() => _CourseEditScreenState();
}

class _CourseEditScreenState extends State<CourseEditScreen> {
  /// 新增时也先定下 ID，让「自动」色板可以稳定预览最终颜色。
  late final String _courseId = widget.course?.id ?? newLocalId('c');

  late final TextEditingController _title =
      TextEditingController(text: widget.course?.title ?? '');
  late final TextEditingController _teacher =
      TextEditingController(text: widget.course?.teacher ?? '');
  late final TextEditingController _location =
      TextEditingController(text: widget.course?.defaultLocation ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.course?.description ?? '');
  final TextEditingController _keywordInput = TextEditingController();

  late String _color = widget.course?.color ?? '';
  late String _icon = widget.course?.icon ?? '';
  late final List<String> _keywords = [...?widget.course?.keywords];
  late final List<Alert> _alerts = [...?widget.course?.alerts];
  late final List<Meeting> _meetings = [...?widget.course?.meetings];

  bool _titleError = false;

  @override
  void dispose() {
    _title.dispose();
    _teacher.dispose();
    _location.dispose();
    _description.dispose();
    _keywordInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course == null ? '添加课程' : '编辑课程'),
        centerTitle: false,
        actions: [
          if (widget.course != null)
            IconButton(
              tooltip: '删除课程',
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
            controller: _title,
            autofocus: widget.course == null,
            decoration: InputDecoration(
              labelText: '课程名称',
              hintText: '如：高等数学',
              border: const OutlineInputBorder(),
              errorText: _titleError ? '请填写课程名称' : null,
            ),
            onChanged: (_) {
              if (_titleError) setState(() => _titleError = false);
            },
          ),
          _sectionLabel(context, '颜色'),
          ColorSwatchRow(
            value: _color,
            emptyLabel: '自动',
            emptyPreview: autoCourseColor(_courseId),
            onChanged: (v) => setState(() => _color = v),
          ),
          _sectionLabel(context, '图标'),
          _iconRow(scheme),
          _sectionLabel(context, '教师与教室'),
          TextField(
            controller: _teacher,
            decoration: const InputDecoration(
              labelText: '任课教师',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _location,
            decoration: const InputDecoration(
              labelText: '默认教室',
              hintText: '如：教三-201',
              helperText: '一学期基本不变的地点；个别时段可在排课里覆盖',
              border: OutlineInputBorder(),
            ),
          ),
          _sectionLabel(context, '标签'),
          if (_keywords.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < _keywords.length; i++)
                    InputChip(
                      label: Text(_keywords[i]),
                      visualDensity: VisualDensity.compact,
                      onDeleted: () => setState(() => _keywords.removeAt(i)),
                    ),
                ],
              ),
            ),
          TextField(
            controller: _keywordInput,
            decoration: InputDecoration(
              labelText: '添加标签',
              hintText: '如：必修、考试',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: '添加标签',
                icon: const Icon(Icons.add),
                onPressed: () => _addKeyword(_keywordInput.text),
              ),
            ),
            onSubmitted: _addKeyword,
          ),
          _sectionLabel(context, '备注'),
          TextField(
            controller: _description,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '如：带计算器',
              border: OutlineInputBorder(),
            ),
          ),
          _sectionLabel(context, '提醒'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (var i = 0; i < _alerts.length; i++)
                InputChip(
                  label: Text(alertLabel(_alerts[i])),
                  visualDensity: VisualDensity.compact,
                  onDeleted: () => setState(() => _alerts.removeAt(i)),
                ),
              ActionChip(
                avatar: const Icon(Icons.add_alert_outlined, size: 18),
                label: const Text('添加提醒'),
                onPressed: _addAlert,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '随课程数据保存；当前通知提醒以「设置」中的全局开关为准。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.outline),
            ),
          ),
          _sectionLabel(context, '排课时段'),
          if (_meetings.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '尚无排课时段；不添加也可保存，但课程不会出现在课表上。',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.outline),
              ),
            )
          else
            for (var i = 0; i < _meetings.length; i++)
              _meetingCard(context, i),
          OutlinedButton.icon(
            onPressed: _addMeeting,
            icon: const Icon(Icons.add),
            label: const Text('添加时段'),
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

  // ---- 图标 ----

  Widget _iconRow(ColorScheme scheme) {
    final names = ['', ...courseIcons.keys];
    if (_icon.isNotEmpty && !courseIcons.containsKey(_icon)) {
      names.insert(1, _icon); // 未知图标名（如外部导入）也可保留选中
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final name in names)
          if (name.isEmpty)
            ChoiceChip(
              label: const Text('无'),
              selected: _icon.isEmpty,
              onSelected: (_) => setState(() => _icon = ''),
            )
          else
            _iconSwatch(scheme, name),
      ],
    );
  }

  Widget _iconSwatch(ColorScheme scheme, String name) {
    final selected = _icon == name;
    return InkWell(
      onTap: () => setState(() => _icon = name),
      customBorder: const CircleBorder(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          shape: BoxShape.circle,
          border: selected ? Border.all(color: scheme.primary, width: 2) : null,
        ),
        child: Icon(
          courseIcon(name) ?? Icons.extension_outlined,
          size: 20,
          color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  // ---- 标签 / 提醒 ----

  void _addKeyword(String raw) {
    final k = raw.trim();
    if (k.isEmpty) return;
    setState(() {
      if (!_keywords.contains(k)) _keywords.add(k);
      _keywordInput.clear();
    });
  }

  Future<void> _addAlert() async {
    const presetMinutes = [0, 5, 10, 15, 20, 30];
    final alert = await showDialog<Alert>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('添加提醒'),
        children: [
          for (final m in presetMinutes)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(
                dialogContext,
                m == 0
                    ? const Alert(offset: Duration.zero)
                    : Alert.beforeStart(Duration(minutes: m)),
              ),
              child: Text(m == 0 ? '上课时' : '上课前 $m 分钟'),
            ),
        ],
      ),
    );
    if (alert == null) return;
    final exists = _alerts.any(
      (a) => a.offset == alert.offset && a.relativeToEnd == alert.relativeToEnd,
    );
    if (!exists) setState(() => _alerts.add(alert));
  }

  // ---- 排课时段 ----

  Widget _meetingCard(BuildContext context, int index) {
    final m = _meetings[index];
    final scheme = Theme.of(context).colorScheme;
    final subtitle = [
      weekRuleLabel(m.weeks),
      if (m.location != null && m.location!.isNotEmpty) '@${m.location}',
      if (m.overrides.isNotEmpty) '${m.overrides.length} 条单次调整',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: ListTile(
        title: Text('${weekdayCnOf(m.weekday)} · ${meetingTimeLabel(m)}'),
        subtitle: Text(subtitle),
        trailing: IconButton(
          tooltip: '删除时段',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => setState(() => _meetings.removeAt(index)),
        ),
        onTap: () => _editMeeting(index),
      ),
    );
  }

  Future<void> _addMeeting() async {
    final created = await _showMeetingSheet(
      Meeting(
        id: newLocalId('m'),
        weekday: widget.initialWeekday ?? DateTime.now().weekday,
        startPeriod: 1,
        endPeriod: 1,
      ),
    );
    if (created != null) setState(() => _meetings.add(created));
  }

  Future<void> _editMeeting(int index) async {
    final updated = await _showMeetingSheet(_meetings[index]);
    if (updated != null) setState(() => _meetings[index] = updated);
  }

  Future<Meeting?> _showMeetingSheet(Meeting initial) {
    final cal = context.read<AppState>().calendar;
    return showModalBottomSheet<Meeting>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: _MeetingSheet(calendar: cal, initial: initial),
      ),
    );
  }

  // ---- 保存 / 删除 ----

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = true);
      return;
    }
    final app = context.read<AppState>();
    final base = widget.course ?? CourseEvent(id: _courseId);

    await app.upsertCourse(base.copyWith(
      title: title,
      color: _color,
      icon: _icon,
      teacher: _teacher.text.trim(),
      defaultLocation: _location.text.trim(),
      keywords: List.of(_keywords),
      description: _description.text.trim(),
      alerts: List.of(_alerts),
      meetings: List.of(_meetings),
    ));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final course = widget.course;
    if (course == null) return;
    final app = context.read<AppState>();
    final navigator = Navigator.of(context);
    if (!await confirmDeleteCourse(context, course.title)) return;
    await app.deleteCourse(course.id);
    navigator.pop();
  }
}

/// 单个排课时段的编辑弹层：星期、按节次或自定义时刻、周次规则、可选的
/// 地点/教师/作息表覆盖。确定后以新 [Meeting] pop 返回（保留原 id、
/// overrides 与 extra）。
class _MeetingSheet extends StatefulWidget {
  final Calendar? calendar;
  final Meeting initial;

  const _MeetingSheet({required this.calendar, required this.initial});

  @override
  State<_MeetingSheet> createState() => _MeetingSheetState();
}

class _MeetingSheetState extends State<_MeetingSheet> {
  /// 周次网格「增加周数」每次放大的格数，以及网格能扩到的上界（防误触无限拉长）。
  static const int _weekGridStep = 5;
  static const int _maxWeekGrid = 60;

  late int _weekday =
      widget.initial.weekday >= 1 && widget.initial.weekday <= 7
          ? widget.initial.weekday
          : 1;
  late LessonTimeValue _time = _initialTime(widget.initial);
  late String? _bellId = widget.initial.bellScheduleId;
  late WeekRule _weeks = widget.initial.weeks;

  late final TextEditingController _location =
      TextEditingController(text: widget.initial.location ?? '');
  late final TextEditingController _teacher =
      TextEditingController(text: widget.initial.teacher ?? '');

  static LessonTimeValue _initialTime(Meeting m) {
    final start = m.startPeriod >= 1 ? m.startPeriod : 1;
    return LessonTimeValue(
      custom: m.usesCustomTime,
      startPeriod: start,
      endPeriod: m.endPeriod >= start ? m.endPeriod : start,
      customStart: timeOfDayFromHhmm(m.customStart),
      customEnd: timeOfDayFromHhmm(m.customEnd),
    );
  }

  @override
  void dispose() {
    _location.dispose();
    _teacher.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '排课时段',
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (widget.initial.overrides.isNotEmpty)
                    Text(
                      '含 ${widget.initial.overrides.length} 条单次调整，保存后保留',
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.outline),
                    ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(context, '星期'),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (var w = 1; w <= 7; w++)
                          ChoiceChip(
                            label: Text(weekdayCnOf(w)),
                            selected: _weekday == w,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => setState(() => _weekday = w),
                          ),
                      ],
                    ),
                    _label(context, '时间'),
                    LessonTimeFields(
                      calendar: widget.calendar,
                      weekday: _weekday,
                      bellScheduleId: _bellId,
                      value: _time,
                      onChanged: (v) => setState(() => _time = v),
                    ),
                    if ((widget.calendar?.bellSchedules.length ?? 0) > 1 &&
                        !_time.custom) ...[
                      _label(context, '作息表'),
                      _bellDropdown(),
                    ],
                    _label(context, '周次'),
                    Card(
                      margin: EdgeInsets.zero,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                      child: ListTile(
                        title: Text(weekRuleLabel(_weeks)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _editWeeks,
                      ),
                    ),
                    _label(context, '本时段覆盖（可选）'),
                    TextField(
                      controller: _location,
                      decoration: const InputDecoration(
                        labelText: '地点',
                        hintText: '留空则用课程默认教室',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _teacher,
                      decoration: const InputDecoration(
                        labelText: '教师',
                        hintText: '留空则用课程任课教师',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      child: const Text('确定'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
        ),
      );

  Widget _bellDropdown() {
    final bells = widget.calendar!.bellSchedules;
    final value = (_bellId != null && bells.containsKey(_bellId)) ? _bellId! : '';
    return InputDecorator(
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        isDense: true,
        underline: const SizedBox.shrink(),
        items: [
          const DropdownMenuItem(value: '', child: Text('跟随课表默认')),
          for (final e in bells.entries)
            DropdownMenuItem(
              value: e.key,
              child: Text(e.value.name.isEmpty ? e.key : e.value.name),
            ),
        ],
        onChanged: (v) =>
            setState(() => _bellId = (v == null || v.isEmpty) ? null : v),
      ),
    );
  }

  Future<void> _editWeeks() async {
    // 学期无固定周数：网格起点取「本课表已排到的最大周」（[Calendar.weekCount]，
    // 兜底 20），再不小于本规则已引用的周，保证已排课程完整可见。用户可按
    // 「增加周数」把网格继续放大，突破 20 周上限（长学期的排课入口）。
    final calWeeks = widget.calendar?.weekCount ?? Calendar.defaultWeekCount;
    var count = weekGridCount(_weeks, defaultWeeks: calWeeks);
    var selected = weeksOfRule(_weeks, count);
    final result = await showDialog<WeekRule>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('选择周次'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final (label, weeks) in [
                        ('全选', {for (var w = 1; w <= count; w++) w}),
                        ('单周', {for (var w = 1; w <= count; w += 2) w}),
                        ('双周', {for (var w = 2; w <= count; w += 2) w}),
                        ('清空', <int>{}),
                      ])
                        ActionChip(
                          label: Text(label),
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              setDialogState(() => selected = {...weeks}),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var w = 1; w <= count; w++)
                        FilterChip(
                          label: Text('$w'),
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          selected: selected.contains(w),
                          onSelected: (on) => setDialogState(() {
                            if (on) {
                              selected.add(w);
                            } else {
                              selected.remove(w);
                            }
                          }),
                        ),
                      if (count < _maxWeekGrid)
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 18),
                          label: const Text('增加周数'),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setDialogState(
                            () => count =
                                (count + _weekGridStep).clamp(0, _maxWeekGrid),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(
                      dialogContext, weekRuleFromWeeks(selected)),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    if (result != null) setState(() => _weeks = result);
  }

  void _submit() {
    if (_time.custom) {
      if (_time.customStart == null || _time.customEnd == null) {
        _snack('请选择开始与结束时间');
        return;
      }
      if (!_time.customTimeValid) {
        _snack('结束时间需晚于开始时间');
        return;
      }
    }
    final loc = _location.text.trim();
    final tch = _teacher.text.trim();
    Navigator.pop(
      context,
      Meeting(
        id: widget.initial.id,
        weekday: _weekday,
        startPeriod: _time.custom ? 0 : _time.startPeriod,
        endPeriod: _time.custom ? 0 : _time.endPeriod,
        customStart:
            _time.custom ? hhmmFromTimeOfDay(_time.customStart!) : null,
        customEnd: _time.custom ? hhmmFromTimeOfDay(_time.customEnd!) : null,
        bellScheduleId: _time.custom ? null : _bellId,
        weeks: _weeks,
        location: loc.isEmpty ? null : loc,
        teacher: tch.isEmpty ? null : tch,
        overrides: widget.initial.overrides,
        extra: widget.initial.extra,
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
