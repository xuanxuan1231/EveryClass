/// 「单次编辑」与「修改本次及以后」的纯计算：把单次编辑表单相对基线的差异
/// 按所选范围落到数据模型上。
///
/// 基线是**页面展示的生效值**（`override ?? meeting ?? course` 逐级回退，与
/// 调度引擎同口径）。补丁语义：只有用户实际改动的字段进入该日
/// [OccurrenceOverride]（仅本次）或新时段的基础值（本次及以后）；改回继承值
/// 则撤销该字段的覆盖；其他日期上已有的单次调整原样保留。
library;

import '../models/course_event.dart';
import '../models/meeting.dart';
import '../models/occurrence_override.dart';
import '../models/week_rule.dart';
import '../util/week_set.dart';

/// 单次编辑表单的一组值（页面展示口径：字符串非 null，'' 即空）。
///
/// 时间二选一：[usesCustomTime] 为真用 [customStart]/[customEnd]（`HH:mm`），
/// 否则用 [startPeriod]/[endPeriod]。
class OccurrenceEdit {
  /// 这次课的生效日期（被调课时为调后的日期）。
  final DateTime date;

  final bool usesCustomTime;
  final int startPeriod;
  final int endPeriod;
  final String? customStart;
  final String? customEnd;

  final String teacher;
  final String location;
  final String description;

  const OccurrenceEdit({
    required this.date,
    required this.usesCustomTime,
    this.startPeriod = 0,
    this.endPeriod = 0,
    this.customStart,
    this.customEnd,
    this.teacher = '',
    this.location = '',
    this.description = '',
  });
}

/// [meeting] 在 [day]（原发生日期）这次课的生效值，作为表单初值与 diff 基线。
OccurrenceEdit effectiveOccurrenceEdit({
  required CourseEvent course,
  required Meeting meeting,
  required DateTime day,
}) {
  final ov = meeting.overrides[ymdKey(day)];
  final customStart = ov?.customStart ?? meeting.customStart;
  final customEnd = ov?.customEnd ?? meeting.customEnd;
  final usesCustom = customStart != null && customStart.isNotEmpty;
  final moved =
      ov?.movedToDate == null ? null : DateTime.tryParse(ov!.movedToDate!);
  final date = moved ?? day;
  return OccurrenceEdit(
    date: DateTime(date.year, date.month, date.day),
    usesCustomTime: usesCustom,
    startPeriod: usesCustom ? 0 : (ov?.startPeriod ?? meeting.startPeriod),
    endPeriod: usesCustom ? 0 : (ov?.endPeriod ?? meeting.endPeriod),
    customStart: usesCustom ? customStart : null,
    customEnd: usesCustom ? customEnd : null,
    teacher: ov?.teacher ?? meeting.teacher ?? course.teacher,
    location: ov?.location ?? meeting.location ?? course.defaultLocation,
    description: ov?.description ?? course.description,
  );
}

/// [edit] 相对基线 [base] 的改动分类，用于决定保存时是否询问应用范围。
class OccurrenceEditDiff {
  final bool date;
  final bool time;
  final bool teacher;
  final bool location;
  final bool description;

  const OccurrenceEditDiff({
    required this.date,
    required this.time,
    required this.teacher,
    required this.location,
    required this.description,
  });

  /// 可「本次及以后」表达的改动（备注只能按次，不在其列）。
  bool get schedule => date || time || teacher || location;

  bool get any => schedule || description;
}

OccurrenceEditDiff diffOccurrenceEdit(OccurrenceEdit base, OccurrenceEdit edit) {
  return OccurrenceEditDiff(
    date: ymdKey(edit.date) != ymdKey(base.date),
    time: edit.usesCustomTime != base.usesCustomTime ||
        edit.customStart != base.customStart ||
        edit.customEnd != base.customEnd ||
        edit.startPeriod != base.startPeriod ||
        edit.endPeriod != base.endPeriod,
    teacher: edit.teacher != base.teacher,
    location: edit.location != base.location,
    description: edit.description != base.description,
  );
}

/// 仅修改本次：把 [edit] 相对生效值的改动合并成 [day] 上的一条
/// [OccurrenceOverride]，返回替换后的时段。
///
/// - 改动字段写入该日补丁；新值等于继承值（`meeting ?? course`）时撤销覆盖；
/// - 日期改动写 `movedToDate`（改回原日期则清除）；
/// - 补课（`added`）的发生日期就是键本身，改日期时**重建键**（调度引擎对
///   added 条目忽略 `movedToDate`）；
/// - 补丁全空时移除该键。
Meeting applyOccurrenceEditThisOnly({
  required CourseEvent course,
  required Meeting meeting,
  required DateTime day,
  required OccurrenceEdit edit,
}) {
  final key = ymdKey(day);
  final existing = meeting.overrides[key];
  final base =
      effectiveOccurrenceEdit(course: course, meeting: meeting, day: day);
  final diff = diffOccurrenceEdit(base, edit);

  final teacher = _diffText(
    changed: diff.teacher,
    edited: edit.teacher,
    inherited: meeting.teacher ?? course.teacher,
    existing: existing?.teacher,
  );
  final location = _diffText(
    changed: diff.location,
    edited: edit.location,
    inherited: meeting.location ?? course.defaultLocation,
    existing: existing?.location,
  );
  final description = _diffText(
    changed: diff.description,
    edited: edit.description,
    inherited: course.description,
    existing: existing?.description,
  );

  final time = _diffTime(meeting: meeting, existing: existing, edit: edit,
      changed: diff.time);

  final overrides = Map<String, OccurrenceOverride>.from(meeting.overrides);

  if (existing != null && existing.added) {
    // 补课：键即发生日期，改日期 = 换键；added 恒保留。
    overrides.remove(key);
    overrides[ymdKey(edit.date)] = OccurrenceOverride(
      added: true,
      startPeriod: time.startPeriod,
      endPeriod: time.endPeriod,
      customStart: time.customStart,
      customEnd: time.customEnd,
      location: location,
      teacher: teacher,
      description: description,
    );
    return meeting.copyWith(overrides: overrides);
  }

  String? movedToDate = existing?.movedToDate;
  if (diff.date) {
    final editedKey = ymdKey(edit.date);
    movedToDate = editedKey == key ? null : editedKey;
  }

  final merged = OccurrenceOverride(
    excluded: existing?.excluded ?? false,
    movedToDate: movedToDate,
    startPeriod: time.startPeriod,
    endPeriod: time.endPeriod,
    customStart: time.customStart,
    customEnd: time.customEnd,
    location: location,
    teacher: teacher,
    description: description,
  );
  if (_isEmptyOverride(merged)) {
    overrides.remove(key);
  } else {
    overrides[key] = merged;
  }
  return meeting.copyWith(overrides: overrides);
}

/// 修改本次及以后：把改动升级为从第 [week] 周（[day] 所在学期周）起的新基础
/// 值，复用 [splitMeetingFromWeek] 拆段。
///
/// - 日期改动取 `edit.date.weekday` 作新基础星期（跨周选日按星期理解）；
/// - [day] 上旧补丁中被升级为新基础值的字段剥离（否则遮住新基础值），其余
///   字段与备注改动作为残留补丁挂回**新段**——改了日期时键平移到本周新日期；
/// - 不适用于补课（added）场景，调用方应按仅本次处理。
List<Meeting> applyOccurrenceEditFromWeek({
  required CourseEvent course,
  required Meeting meeting,
  required DateTime day,
  required int week,
  required String newId,
  required OccurrenceEdit edit,
}) {
  final key = ymdKey(day);
  final existing = meeting.overrides[key];
  final base =
      effectiveOccurrenceEdit(course: course, meeting: meeting, day: day);
  final diff = diffOccurrenceEdit(base, edit);

  String? baseText(bool changed, String edited, String inherited, String? old) {
    if (!changed) return old;
    return edited.isEmpty || edited == inherited ? null : edited;
  }

  final edited = Meeting(
    id: meeting.id, // 仅取字段；新段 id 由 splitMeetingFromWeek 用 newId
    weekday: diff.date ? edit.date.weekday : meeting.weekday,
    startPeriod: !diff.time
        ? meeting.startPeriod
        : (edit.usesCustomTime ? 0 : edit.startPeriod),
    endPeriod: !diff.time
        ? meeting.endPeriod
        : (edit.usesCustomTime ? 0 : edit.endPeriod),
    customStart: diff.time ? edit.customStart : meeting.customStart,
    customEnd: diff.time ? edit.customEnd : meeting.customEnd,
    bellScheduleId: meeting.bellScheduleId,
    weeks: meeting.weeks,
    location: baseText(
        diff.location, edit.location, course.defaultLocation, meeting.location),
    teacher:
        baseText(diff.teacher, edit.teacher, course.teacher, meeting.teacher),
    extra: meeting.extra,
  );

  // 该日残留补丁：被升级的字段剥离，备注按 diff 写，其余保留。
  final residual = OccurrenceOverride(
    excluded: existing?.excluded ?? false,
    movedToDate: diff.date ? null : existing?.movedToDate,
    startPeriod: diff.time ? null : existing?.startPeriod,
    endPeriod: diff.time ? null : existing?.endPeriod,
    customStart: diff.time ? null : existing?.customStart,
    customEnd: diff.time ? null : existing?.customEnd,
    location: diff.location ? null : existing?.location,
    teacher: diff.teacher ? null : existing?.teacher,
    description: !diff.description
        ? existing?.description
        : (edit.description == course.description ? null : edit.description),
  );

  final overrides = Map<String, OccurrenceOverride>.from(meeting.overrides)
    ..remove(key);
  final parts = splitMeetingFromWeek(
    original: meeting.copyWith(overrides: overrides),
    edited: edited,
    day: day,
    week: week,
    newId: newId,
  );
  if (_isEmptyOverride(residual)) return parts;

  // 残留补丁挂回新段；改了日期时，这次课落到本周的新星期上。
  final residualKey = diff.date
      ? ymdKey(day.add(Duration(days: edit.date.weekday - day.weekday)))
      : key;
  return [
    for (final p in parts)
      p.id == newId
          ? p.copyWith(overrides: {...p.overrides, residualKey: residual})
          : p,
  ];
}

/// 本次停课：常规课在该日补丁上置 `excluded`（时刻/教师等字段保留，
/// `movedToDate` 清除——调课后的停课即整次取消）；补课（added）直接移除。
Meeting cancelOccurrence(Meeting meeting, DateTime day) {
  final key = ymdKey(day);
  final existing = meeting.overrides[key];
  final overrides = Map<String, OccurrenceOverride>.from(meeting.overrides);
  if (existing != null && existing.added) {
    overrides.remove(key);
  } else {
    overrides[key] = OccurrenceOverride(
      excluded: true,
      startPeriod: existing?.startPeriod,
      endPeriod: existing?.endPeriod,
      customStart: existing?.customStart,
      customEnd: existing?.customEnd,
      location: existing?.location,
      teacher: existing?.teacher,
      description: existing?.description,
    );
  }
  return meeting.copyWith(overrides: overrides);
}

/// 文本字段的补丁值：未改动保留原覆盖；改动后等于继承值则撤销（null），
/// 否则写新值（'' 表示本次显式清空）。
String? _diffText({
  required bool changed,
  required String edited,
  required String inherited,
  required String? existing,
}) {
  if (!changed) return existing;
  return edited == inherited ? null : edited;
}

class _TimePatch {
  final int? startPeriod;
  final int? endPeriod;
  final String? customStart;
  final String? customEnd;
  const _TimePatch(
      this.startPeriod, this.endPeriod, this.customStart, this.customEnd);
}

/// 时间字段的补丁值：改回与时段一致 → 全部撤销；改成自定义 → 写时刻；改成
/// 节次 → 写节次，且当时段本身是自定义时刻时用空串压掉（调度引擎对空串按
/// 「未设」处理）。
_TimePatch _diffTime({
  required Meeting meeting,
  required OccurrenceOverride? existing,
  required OccurrenceEdit edit,
  required bool changed,
}) {
  if (!changed) {
    return _TimePatch(existing?.startPeriod, existing?.endPeriod,
        existing?.customStart, existing?.customEnd);
  }
  final sameAsMeeting = edit.usesCustomTime == meeting.usesCustomTime &&
      (edit.usesCustomTime
          ? (edit.customStart == meeting.customStart &&
              edit.customEnd == meeting.customEnd)
          : (edit.startPeriod == meeting.startPeriod &&
              edit.endPeriod == meeting.endPeriod));
  if (sameAsMeeting) return const _TimePatch(null, null, null, null);
  if (edit.usesCustomTime) {
    return _TimePatch(null, null, edit.customStart, edit.customEnd);
  }
  return _TimePatch(
    edit.startPeriod,
    edit.endPeriod,
    meeting.usesCustomTime ? '' : null,
    meeting.usesCustomTime ? '' : null,
  );
}

bool _isEmptyOverride(OccurrenceOverride o) =>
    !o.excluded &&
    !o.added &&
    o.movedToDate == null &&
    o.startPeriod == null &&
    o.endPeriod == null &&
    o.customStart == null &&
    o.customEnd == null &&
    o.location == null &&
    o.teacher == null &&
    o.description == null;

/// 修改本次及以后：把时段在第 [week]（[day] 所在学期周）处一分为二。
///
/// 旧时段保持原样、周次截到第 [week] 周之前；新时段（id 为 [newId]）用
/// [edited] 的字段、周次从第 [week] 周起。已有单次调整按「原发生日期」
/// 分家：早于 [day] 的留在旧段，其余随新段（补丁字段不被触碰，未覆盖的
/// 字段自动跟随新基础值）。
///
/// 无上界的周次规则（如「每周」）拆分后仍保持无上界——学期周数没有上限，
/// 不能按默认网格截断。
///
/// 返回替换用的时段列表（旧段若已无任何周次与调整则不保留）。
List<Meeting> splitMeetingFromWeek({
  required Meeting original,
  required Meeting edited,
  required DateTime day,
  required int week,
  required String newId,
}) {
  final key = ymdKey(day);
  final pastRule = _ruleBefore(original.weeks, week);
  final futureRule = _ruleFrom(edited.weeks, week);

  final pastOv = <String, OccurrenceOverride>{};
  final futureOv = <String, OccurrenceOverride>{};
  for (final e in original.overrides.entries) {
    (e.key.compareTo(key) < 0 ? pastOv : futureOv)[e.key] = e.value;
  }

  final out = <Meeting>[];
  if (pastRule != null || pastOv.isNotEmpty) {
    out.add(original.copyWith(
      // 只剩单次调整（补课/调课）时用永不命中的规则，不再产生常规重复。
      weeks: pastRule ?? _neverRule,
      overrides: pastOv,
    ));
  }
  if (futureRule != null || futureOv.isNotEmpty) {
    out.add(Meeting(
      id: newId,
      weekday: edited.weekday,
      startPeriod: edited.startPeriod,
      endPeriod: edited.endPeriod,
      customStart: edited.customStart,
      customEnd: edited.customEnd,
      bellScheduleId: edited.bellScheduleId,
      weeks: futureRule ?? _neverRule,
      location: edited.location,
      teacher: edited.teacher,
      overrides: futureOv,
      extra: edited.extra,
    ));
  }
  return out;
}

/// 无上界规则：没有范围上界也没有显式周列表，周次可无限延伸。
bool _isUnboundedRule(WeekRule r) => r.toWeek <= 0 && r.include.isEmpty;

/// [rule] 限制到第 [week] 周之前（不含）的部分；一个周都不命中则 null。
/// 有界规则枚举周次后重新规约（网格必不小于其上界，无损）；无上界规则直接
/// 收紧上界，避免按默认网格把「无限」截成 20 周。
WeekRule? _ruleBefore(WeekRule rule, int week) {
  if (_isUnboundedRule(rule)) {
    if (week <= 1 || week <= rule.fromWeek) return null;
    final bounded = rule.copyWith(toWeek: week - 1);
    return weeksOfRule(bounded, week - 1).isEmpty ? null : bounded;
  }
  final weeks =
      weeksOfRule(rule, weekGridCount(rule)).where((w) => w < week).toSet();
  return weeks.isEmpty ? null : weekRuleFromWeeks(weeks);
}

/// [rule] 从第 [week] 周起（含）的部分；一个周都不命中则 null。无上界规则
/// 保持无上界（轮换 offset 以学期周为绝对基准，收紧 fromWeek 不改变相位）。
WeekRule? _ruleFrom(WeekRule rule, int week) {
  if (_isUnboundedRule(rule)) {
    return week <= rule.fromWeek ? rule : rule.copyWith(fromWeek: week);
  }
  final weeks =
      weeksOfRule(rule, weekGridCount(rule)).where((w) => w >= week).toSet();
  return weeks.isEmpty ? null : weekRuleFromWeeks(weeks);
}

/// 不命中任何周次的规则（fromWeek > toWeek 恒为假）。
const WeekRule _neverRule = WeekRule(fromWeek: 2, toWeek: 1);

/// `yyyy-MM-dd`（补零到 4 位年），与 [Meeting.overrides] 的键口径一致。
String ymdKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
