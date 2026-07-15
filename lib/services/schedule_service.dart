import '../models/bell_schedule.dart';
import '../models/calendar.dart';
import '../models/course_event.dart';
import '../models/meeting.dart';
import '../models/occurrence_override.dart';
import '../models/resolved_lesson.dart';
import '../util/coerce.dart';

/// 某一天解析后的课表。
class DaySchedule {
  final DateTime day;
  final List<ResolvedLesson> lessons;

  const DaySchedule({required this.day, required this.lessons});

  bool get isEmpty => lessons.isEmpty;
}

/// 一段空闲时间（距零点的起止）。
class FreeSlot {
  final Duration start;
  final Duration end;
  const FreeSlot(this.start, this.end);

  Duration get length => end - start;
}

/// 调度引擎：把一张 [Calendar] 投影成「某天的具体课表」，并给出当前/下一节、
/// 冲突检测与空闲时间。纯计算、无副作用。
///
/// 星期口径：`DateTime.weekday` 与 `Meeting.weekday` 都是 1–7、周一=1。
class ScheduleService {
  final Calendar calendar;

  const ScheduleService(this.calendar);

  /// 目标日 [day] 的 1-based 学期周；未设 firstWeekStart 时返回 null。
  int? weekOf(DateTime day) {
    final fws = calendar.firstWeekStart;
    if (fws == null) return null;
    final start = _mondayOf(fws);
    final d0 = DateTime(day.year, day.month, day.day);
    final diff = d0.difference(start).inDays;
    if (diff < 0) return null;
    return diff ~/ 7 + 1;
  }

  DaySchedule scheduleFor(DateTime day) {
    final week = weekOf(day);
    final weekday = day.weekday;
    final dateKey = _ymd(day);

    final resolved = <ResolvedLesson>[];
    for (final course in calendar.courses.values) {
      for (final meeting in course.meetings) {
        final lesson = _resolveOccurrence(
          course,
          meeting,
          day,
          weekday,
          week,
          dateKey,
        );
        if (lesson != null) resolved.add(lesson);
      }
    }

    // 按开始时刻排序，再赋 1-based period（当天顺序序号）。
    resolved.sort((a, b) => a.start.compareTo(b.start));
    final withPeriod = <ResolvedLesson>[];
    for (var i = 0; i < resolved.length; i++) {
      withPeriod.add(_withPeriod(resolved[i], i + 1));
    }
    return DaySchedule(day: day, lessons: withPeriod);
  }

  /// 把一条 Meeting 在 [day] 的这次课解析成 [ResolvedLesson]；不生效则 null。
  ///
  /// 优先级：先看本 Meeting 有没有以 [day] 为「原发生日期」的例外（停课/调课/
  /// 改教室）；再看有没有别的日期调课/补课「落到」了 [day]。
  ResolvedLesson? _resolveOccurrence(
    CourseEvent course,
    Meeting meeting,
    DateTime day,
    int weekday,
    int? week,
    String dateKey,
  ) {
    // 1) 本日是否有以「原发生日期=本日」为键的补课（added）。
    final addedHere = meeting.overrides[dateKey];
    if (addedHere != null && addedHere.added) {
      return _build(course, meeting, day, weekday,
          override: addedHere, originDate: dateKey);
    }

    // 2) 别处调课搬到了本日？扫描所有 movedToDate==本日 的例外。
    for (final entry in meeting.overrides.entries) {
      final ov = entry.value;
      if (ov.excluded) continue; // 调课后又停课：整次取消，目标日也不出现
      if (ov.movedToDate == dateKey) {
        // 用「原发生日期」的星期取默认作息，但排到本日。
        final origin = DateTime.tryParse(entry.key);
        final originWeekday = origin?.weekday ?? weekday;
        return _build(course, meeting, day, originWeekday,
            override: ov, originDate: entry.key);
      }
    }

    // 3) 常规重复：星期 + 周次规则命中。
    if (meeting.weekday != weekday) return null;
    if (week != null && !meeting.weeks.matches(week)) return null;

    final ov = meeting.overrides[dateKey];
    if (ov != null) {
      if (ov.excluded) return null; // 停课
      if (ov.movedToDate != null && ov.movedToDate != dateKey) {
        return null; // 调走了，本日不再有（会在第 2 步于目标日生成）
      }
      return _build(course, meeting, day, weekday,
          override: ov, originDate: dateKey);
    }
    return _build(course, meeting, day, weekday, originDate: dateKey);
  }

  /// 解析时刻 + 教室 + 教师，产出未编号的 ResolvedLesson；解析不出时刻则 null。
  ResolvedLesson? _build(
    CourseEvent course,
    Meeting meeting,
    DateTime day,
    int weekday, {
    OccurrenceOverride? override,
    String originDate = '',
  }) {
    final customStart = override?.customStart ?? meeting.customStart;
    final customEnd = override?.customEnd ?? meeting.customEnd;

    Duration? start;
    Duration? end;
    var startPeriod = override?.startPeriod ?? meeting.startPeriod;
    var endPeriod = override?.endPeriod ?? meeting.endPeriod;

    if (customStart != null && customStart.isNotEmpty) {
      start = parseHhmm(customStart);
      end = parseHhmm(customEnd);
      startPeriod = 0;
      endPeriod = 0;
    } else {
      final schedule = _bellFor(meeting, weekday);
      if (schedule == null) return null;
      final byIndex = schedule.classByIndex;
      final s = byIndex[startPeriod];
      final e = byIndex[endPeriod == 0 ? startPeriod : endPeriod];
      if (s == null) return null;
      start = s.start;
      end = (e ?? s).end;
    }
    if (start == null || end == null) return null;

    final room = override?.location ?? meeting.location ?? course.defaultLocation;
    final teacher = override?.teacher ?? meeting.teacher ?? course.teacher;
    final description = override?.description ?? course.description;

    return ResolvedLesson(
      subjectId: course.id,
      subjectName: course.title,
      teacher: teacher,
      room: room,
      start: start,
      end: end,
      period: 0,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      color: course.color,
      description: description,
      meetingId: meeting.id,
      originDate: originDate,
    );
  }

  BellSchedule? _bellFor(Meeting meeting, int weekday) {
    final id = meeting.bellScheduleId;
    if (id != null && calendar.bellSchedules[id] != null) {
      return calendar.bellSchedules[id];
    }
    return calendar.bellScheduleForWeekday(weekday);
  }

  ResolvedLesson _withPeriod(ResolvedLesson l, int period) => ResolvedLesson(
        subjectId: l.subjectId,
        subjectName: l.subjectName,
        teacher: l.teacher,
        room: l.room,
        start: l.start,
        end: l.end,
        period: period,
        startPeriod: l.startPeriod,
        endPeriod: l.endPeriod,
        color: l.color,
        description: l.description,
        meetingId: l.meetingId,
        originDate: l.originDate,
      );

  /// 当前正在上的课；无则 null。
  ResolvedLesson? currentLesson(DateTime now) {
    for (final l in scheduleFor(now).lessons) {
      if (l.isCurrentAt(now)) return l;
    }
    return null;
  }

  /// 今天尚未开始的下一节课；无则 null。
  ResolvedLesson? nextLesson(DateTime now) {
    for (final l in scheduleFor(now).lessons) {
      if (l.startOn(now).isAfter(now)) return l;
    }
    return null;
  }

  /// 某天的时间冲突：任意两节课时间区间重叠即为一对冲突。
  List<(ResolvedLesson, ResolvedLesson)> conflicts(DateTime day) {
    final lessons = scheduleFor(day).lessons;
    final out = <(ResolvedLesson, ResolvedLesson)>[];
    for (var i = 0; i < lessons.length; i++) {
      for (var j = i + 1; j < lessons.length; j++) {
        final a = lessons[i];
        final b = lessons[j];
        if (a.start < b.end && b.start < a.end) out.add((a, b));
      }
    }
    return out;
  }

  /// 某天在 [from]–[to] 窗口内、未被课程占用的空闲时段。
  List<FreeSlot> freeSlots(
    DateTime day, {
    Duration from = const Duration(hours: 8),
    Duration to = const Duration(hours: 21),
  }) {
    final busy = scheduleFor(day).lessons
        .map((l) => FreeSlot(l.start, l.end))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final out = <FreeSlot>[];
    var cursor = from;
    for (final b in busy) {
      if (b.end <= cursor) continue;
      if (b.start > cursor) {
        out.add(FreeSlot(cursor, b.start < to ? b.start : to));
      }
      if (b.end > cursor) cursor = b.end;
      if (cursor >= to) break;
    }
    if (cursor < to) out.add(FreeSlot(cursor, to));
    return out.where((s) => s.length > Duration.zero).toList();
  }

  DateTime _mondayOf(DateTime d) {
    final dd = DateTime(d.year, d.month, d.day);
    return dd.subtract(Duration(days: dd.weekday - 1));
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
