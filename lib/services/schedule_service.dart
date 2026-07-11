import '../models/class_plan.dart';
import '../models/profile.dart';
import '../models/resolved_lesson.dart';

/// 某一天解析后的课表。
class DaySchedule {
  final DateTime day;
  final List<ResolvedLesson> lessons;

  const DaySchedule({required this.day, required this.lessons});

  bool get isEmpty => lessons.isEmpty;
}

/// 调度引擎：把 [Profile] 投影成"某天的具体课表"，并给出当前/下一节。
///
/// 纯计算、无副作用，便于单元测试。星期口径与 ClassIsland 对齐：`DateTime.weekday`
/// 与 `TimeRule.weekDay` 都是 1–7、周一=1。
class ScheduleService {
  final Profile profile;

  /// 学期第一周所在的日期（用于计算轮换周序）。null 表示不做轮换过滤。
  final DateTime? termStart;

  const ScheduleService(this.profile, {this.termStart});

  DaySchedule scheduleFor(DateTime day) {
    final plan = _selectPlan(day, day.weekday);
    if (plan == null) return DaySchedule(day: day, lessons: const []);

    final layout = profile.timeLayouts[plan.timeLayoutId];
    if (layout == null) return DaySchedule(day: day, lessons: const []);

    final lessons = <ResolvedLesson>[];
    var classIdx = 0;
    var period = 0;
    for (final item in layout.items) {
      if (!item.isLesson) continue;
      period++;
      // classes[i] 依次对应第 i 个上课时间点（ClassIsland 约定）。
      final info =
          classIdx < plan.classes.length ? plan.classes[classIdx] : null;
      classIdx++;
      if (info == null || info.subjectId.isEmpty || !info.isEnabled) continue;
      final subject = profile.subjects[info.subjectId];
      if (subject == null) continue;
      final room = info.room.isNotEmpty ? info.room : subject.defaultRoom;
      lessons.add(
        ResolvedLesson(
          subjectId: info.subjectId,
          subject: subject,
          room: room,
          start: item.start,
          end: item.end,
          period: period,
        ),
      );
    }
    return DaySchedule(day: day, lessons: lessons);
  }

  /// 选出当天生效的课表：weekDay 命中；轮换周命中的精确课表优先于"每周"课表。
  ClassPlan? _selectPlan(DateTime day, int weekday) {
    ClassPlan? everyWeek;
    for (final plan in profile.classPlans.values) {
      if (!plan.isEnabled || plan.isOverlay) continue;
      if (plan.timeRule.weekDay != weekday) continue;
      if (plan.timeRule.weekCountDiv == 0) {
        everyWeek ??= plan;
      } else if (_matchesWeekCycle(day, plan.timeRule)) {
        return plan;
      }
    }
    return everyWeek;
  }

  bool _matchesWeekCycle(DateTime day, TimeRule rule) {
    if (termStart == null) return true; // 未设学期起始日 → 不过滤轮换
    final total = rule.weekCountDivTotal <= 0 ? 2 : rule.weekCountDivTotal;
    return (_weekIndex(day) % total) + 1 == rule.weekCountDiv;
  }

  /// 从学期起始周的周一算起、目标日所在周的 0-based 序号。
  int _weekIndex(DateTime day) {
    final start = _mondayOf(termStart!);
    final d0 = DateTime(day.year, day.month, day.day);
    final diffDays = d0.difference(start).inDays;
    return diffDays >= 0 ? diffDays ~/ 7 : (diffDays - 6) ~/ 7;
  }

  DateTime _mondayOf(DateTime d) {
    final dd = DateTime(d.year, d.month, d.day);
    return dd.subtract(Duration(days: dd.weekday - 1));
  }

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
}
