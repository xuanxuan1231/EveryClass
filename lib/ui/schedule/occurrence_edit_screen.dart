import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/course_event.dart';
import '../../models/meeting.dart';
import '../../util/edit_scope.dart';
import '../../util/format.dart';
import '../../util/local_id.dart';
import 'course_edit_screen.dart';
import 'course_icons.dart';
import 'lesson_colors.dart';
import 'time_fields.dart';

/// 单次编辑页：只调整某一天的这节课——日期（调课）、时间（节次或自定义
/// 时刻）、教师、教室、备注，以及「本次停课」。课程全局信息（名称/颜色/
/// 图标/默认教师/默认教室/默认备注/标签/提醒）只读展示，修改走「编辑课程」。
///
/// 保存时：只改了备注 → 直接按仅本次落补丁；改了日期/时间/教师/教室 →
/// 询问「仅修改本次 / 修改本次及以后」（未设第一周日期、或本次是补课
/// added 时不询问，恒为仅本次）。纯计算见 `util/edit_scope.dart`。
class OccurrenceEditScreen extends StatefulWidget {
  final String courseId;
  final String meetingId;

  /// 这次课的「原发生日期」（[Meeting.overrides] 的键口径）。
  final DateTime date;

  const OccurrenceEditScreen({
    super.key,
    required this.courseId,
    required this.meetingId,
    required this.date,
  });

  @override
  State<OccurrenceEditScreen> createState() => _OccurrenceEditScreenState();
}

/// 保存范围：仅这一次 / 这一次及以后。
enum _SaveScope { thisOnly, thisAndFuture }

class _OccurrenceEditScreenState extends State<OccurrenceEditScreen> {
  /// 打开时刻的生效值基线；保存按与它的 diff 落库。之后课程默认值再变，
  /// 表单里已展示的值不跟着动（与用户看到并确认的内容一致）。
  OccurrenceEdit? _base;

  late DateTime _date = widget.date;
  LessonTimeValue _time = const LessonTimeValue(custom: false);
  final TextEditingController _teacher = TextEditingController();
  final TextEditingController _location = TextEditingController();
  final TextEditingController _description = TextEditingController();

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final course = app.calendar?.courses[widget.courseId];
    final meeting = _meetingOf(course);
    if (course == null || meeting == null) return; // build 里兜底 pop
    final base = effectiveOccurrenceEdit(
      course: course,
      meeting: meeting,
      day: widget.date,
    );
    _base = base;
    _date = base.date;
    final start = base.startPeriod >= 1 ? base.startPeriod : 1;
    _time = LessonTimeValue(
      custom: base.usesCustomTime,
      startPeriod: start,
      endPeriod: base.endPeriod >= start ? base.endPeriod : start,
      customStart: timeOfDayFromHhmm(base.customStart),
      customEnd: timeOfDayFromHhmm(base.customEnd),
    );
    _teacher.text = base.teacher;
    _location.text = base.location;
    _description.text = base.description;
  }

  @override
  void dispose() {
    _teacher.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  Meeting? _meetingOf(CourseEvent? course) {
    for (final m in course?.meetings ?? const <Meeting>[]) {
      if (m.id == widget.meetingId) return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final course = app.calendar?.courses[widget.courseId];
    final meeting = _meetingOf(course);
    if (course == null || meeting == null || _base == null) {
      // 课程或时段已不存在（如在「编辑课程」里被删除），本页无从编辑。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑本次'),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: () => _save(course, meeting),
              child: const Text('保存'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _courseInfoCard(context, course),
          _sectionLabel(context, '日期'),
          _dateTile(context),
          _sectionLabel(context, '时间'),
          LessonTimeFields(
            calendar: app.calendar,
            // 与调度引擎同口径：按原发生日期的星期解析作息。
            weekday: widget.date.weekday,
            bellScheduleId: meeting.bellScheduleId,
            value: _time,
            onChanged: (v) => setState(() => _time = v),
          ),
          _sectionLabel(context, '教师与教室'),
          TextField(
            controller: _teacher,
            decoration: const InputDecoration(
              labelText: '本次教师',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _location,
            decoration: const InputDecoration(
              labelText: '本次教室',
              border: OutlineInputBorder(),
            ),
          ),
          _sectionLabel(context, '本次备注'),
          TextField(
            controller: _description,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '只对这一次课生效',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            icon: const Icon(Icons.event_busy_outlined, size: 18),
            label: const Text('本次停课'),
            onPressed: () => _cancelThis(course, meeting),
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

  // ---- 只读的课程全局信息 ----

  Widget _courseInfoCard(BuildContext context, CourseEvent course) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = courseDisplayColor(course.id, course.title, course.color);
    final icon = courseIcon(course.icon);
    String dash(String s) => s.isEmpty ? '—' : s;
    return Card(
      margin: const EdgeInsets.only(top: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  child: icon != null
                      ? Icon(icon, size: 18)
                      : Text(
                          course.title.isEmpty
                              ? '?'
                              : course.title.characters.first,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    course.title,
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CourseEditScreen(course: course),
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('编辑课程'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _infoRow(context, '默认教师', dash(course.teacher)),
            _infoRow(context, '默认教室', dash(course.defaultLocation)),
            _infoRow(context, '默认备注', dash(course.description)),
            if (course.keywords.isNotEmpty)
              _infoRow(context, '标签', course.keywords.join('、')),
            if (course.alerts.isNotEmpty)
              _infoRow(
                  context, '提醒', course.alerts.map(alertLabel).join('、')),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '全局信息在此只读；名称、颜色、排课等请点「编辑课程」修改。',
                style: textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  // ---- 日期 ----

  Widget _dateTile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final moved = ymdKey(_date) != ymdKey(widget.date);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: ListTile(
        leading: const Icon(Icons.event_outlined),
        title: Text('${ymd(_date)} ${weekdayCn(_date)}'),
        subtitle: moved ? Text('已从 ${ymd(widget.date)} 调课') : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: _pickDate,
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 1),
      lastDate: DateTime(_date.year + 2),
    );
    if (picked == null) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
  }

  // ---- 保存 / 停课 ----

  OccurrenceEdit? _collectEdit() {
    if (_time.custom) {
      if (_time.customStart == null || _time.customEnd == null) {
        _snack('请选择开始与结束时间');
        return null;
      }
      if (!_time.customTimeValid) {
        _snack('结束时间需晚于开始时间');
        return null;
      }
    }
    return OccurrenceEdit(
      date: _date,
      usesCustomTime: _time.custom,
      startPeriod: _time.custom ? 0 : _time.startPeriod,
      endPeriod: _time.custom ? 0 : _time.endPeriod,
      customStart: _time.custom ? hhmmFromTimeOfDay(_time.customStart!) : null,
      customEnd: _time.custom ? hhmmFromTimeOfDay(_time.customEnd!) : null,
      teacher: _teacher.text.trim(),
      location: _location.text.trim(),
      description: _description.text.trim(),
    );
  }

  Future<void> _save(CourseEvent course, Meeting meeting) async {
    final app = context.read<AppState>();
    final edit = _collectEdit();
    if (edit == null) return;
    final diff = diffOccurrenceEdit(_base!, edit);
    if (!diff.any) {
      Navigator.of(context).pop();
      return;
    }

    final isAdded =
        meeting.overrides[ymdKey(widget.date)]?.added ?? false;
    final week = app.schedule?.weekOf(widget.date);

    var scope = _SaveScope.thisOnly;
    if (diff.schedule && week != null && !isAdded) {
      final asked = await _askScope();
      if (asked == null) return; // 取消保存
      scope = asked;
    }

    final replacement = scope == _SaveScope.thisAndFuture
        ? applyOccurrenceEditFromWeek(
            course: course,
            meeting: meeting,
            day: widget.date,
            week: week!,
            newId: newLocalId('m'),
            edit: edit,
          )
        : [
            applyOccurrenceEditThisOnly(
              course: course,
              meeting: meeting,
              day: widget.date,
              edit: edit,
            ),
          ];

    await app.upsertCourse(course.copyWith(meetings: [
      for (final m in course.meetings)
        if (m.id == meeting.id) ...replacement else m,
    ]));
    if (mounted) Navigator.of(context).pop();
  }

  Future<_SaveScope?> _askScope() {
    return showDialog<_SaveScope>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('应用到哪些课？'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, _SaveScope.thisOnly),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.event_outlined),
              title: Text('仅修改本次'),
              subtitle: Text('只调整这一天，其余照旧'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(dialogContext, _SaveScope.thisAndFuture),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.fast_forward_outlined),
              title: Text('修改本次及以后'),
              subtitle: Text('本周起生效，之前的周次与单次调整不受影响'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelThis(CourseEvent course, Meeting meeting) async {
    final app = context.read<AppState>();
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('本次停课'),
          content: Text(
              '「${course.title}」${ymd(widget.date)} ${weekdayCn(widget.date)} 的这节课将从课表移除，其余周次照旧。'),
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
              child: const Text('停课'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    final updated = cancelOccurrence(meeting, widget.date);
    await app.upsertCourse(course.copyWith(meetings: [
      for (final m in course.meetings) m.id == meeting.id ? updated : m,
    ]));
    navigator.pop();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
