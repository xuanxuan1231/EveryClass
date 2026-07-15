import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/bell_schedule.dart';
import '../../models/calendar.dart';
import '../../models/resolved_lesson.dart';
import '../../util/dates.dart';
import '../../util/format.dart';
import 'course_edit_screen.dart';
import 'empty_schedule_hint.dart';
import 'lesson_colors.dart';
import 'lesson_detail_sheet.dart';

const double _rowHeight = 64;
const double _timeColumnWidth = 44;

/// 周视图：WakeUp 风格的节次网格，左右滑动翻周（PageView）。
///
/// 行=节次（作息表 `BellPeriod.index`），列=星期一至日；左列是节次+时刻，
/// 课程按起止节次画成跨行彩色卡片，点按弹出详情。
class WeekViewScreen extends StatefulWidget {
  const WeekViewScreen({super.key});

  @override
  State<WeekViewScreen> createState() => _WeekViewScreenState();
}

class _WeekViewScreenState extends State<WeekViewScreen> {
  late final PageController _pageController =
      PageController(initialPage: weekPageOf(DateTime.now()));
  DateTime _monday = mondayOf(DateTime.now());

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToThisWeek() {
    if (!_pageController.hasClients) return;
    final target = weekPageOf(DateTime.now());
    // 跨度太大时直接跳页，避免长距离翻页动画。
    if ((target - weekPageOf(_monday)).abs() > 8) {
      _pageController.jumpToPage(target);
    } else {
      _pageController.animateToPage(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final week = app.schedule?.weekOf(_monday);
    final monthLabel = '${_monday.year}年${_monday.month}月';
    // 主壳（外层 Scaffold）的抽屉；独立使用本页时没有，则不显示菜单键。
    final shell = Scaffold.maybeOf(context);

    return Scaffold(
      appBar: AppBar(
        leading: (shell?.hasDrawer ?? false)
            ? IconButton(
                tooltip: '打开菜单',
                icon: const Icon(Icons.menu),
                onPressed: shell!.openDrawer,
              )
            : null,
        title: week == null
            ? Text(monthLabel)
            : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('第 $week 周'),
                  const SizedBox(width: 8),
                  Text(
                    monthLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
        centerTitle: false,
        actions: [
          if (!isSameDay(_monday, mondayOf(DateTime.now())))
            IconButton(
              tooltip: '回到本周',
              icon: const Icon(Icons.today_outlined),
              onPressed: _goToThisWeek,
            ),
          IconButton(
            tooltip: '添加课程',
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CourseEditScreen(),
              ),
            ),
          ),
        ],
      ),
      body: !app.hasSchedule
          ? const EmptySchedulePlaceholder()
          : PageView.builder(
              controller: _pageController,
              onPageChanged: (page) =>
                  setState(() => _monday = mondayFromPage(page)),
              itemBuilder: (context, page) =>
                  _WeekPage(app: app, monday: mondayFromPage(page)),
            ),
    );
  }
}

/// 一周的网格页。
class _WeekPage extends StatelessWidget {
  final AppState app;
  final DateTime monday;

  const _WeekPage({required this.app, required this.monday});

  @override
  Widget build(BuildContext context) {
    final cal = app.calendar;
    final svc = app.schedule;
    if (cal == null || svc == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(monday.year, monday.month, monday.day + i),
    ];
    // 网格行数 = 全部作息表中最大的节次序号；无节次时兜底 8 行。
    final rows = cal.maxClassPeriod > 0 ? cal.maxClassPeriod : 8;
    final timeBell = _timeColumnBell(cal);
    final today = dateOnly(DateTime.now());
    final placedByDay = [
      for (final d in days)
        _layoutDay(
          svc.scheduleFor(d).lessons,
          cal.bellScheduleForWeekday(d.weekday) ?? timeBell,
          rows,
        ),
    ];

    return Column(
      children: [
        _WeekHeader(monday: monday, days: days, today: today),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            child: SizedBox(
              height: rows * _rowHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _GridPainter(
                        rows: rows,
                        lineColor:
                            scheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TimeColumn(rows: rows, bell: timeBell),
                      for (var i = 0; i < 7; i++)
                        Expanded(
                          child: _DayColumn(
                            placed: placedByDay[i],
                            isToday: isSameDay(days[i], today),
                            onTapLesson: (lesson) => showLessonDetailSheet(
                              context,
                              lesson: lesson,
                              day: days[i],
                              course: cal.courses[lesson.subjectId],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 表头：左侧月份 + 7 天（星期单字 + 月/日，今天高亮）。
class _WeekHeader extends StatelessWidget {
  final DateTime monday;
  final List<DateTime> days;
  final DateTime today;

  const _WeekHeader({
    required this.monday,
    required this.days,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: _timeColumnWidth,
            child: Center(
              child: Text(
                '${monday.month}月',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          for (final d in days)
            Expanded(child: _headerCell(context, d, isSameDay(d, today))),
        ],
      ),
    );
  }

  Widget _headerCell(BuildContext context, DateTime day, bool isToday) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          weekdayShortCn(day),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: isToday ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: isToday ? FontWeight.bold : null,
              ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: isToday
              ? BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(10),
                )
              : null,
          child: Text(
            '${day.month}/${day.day}',
            style: TextStyle(
              fontSize: 10,
              color: isToday ? scheme.onPrimary : scheme.outline,
            ),
          ),
        ),
      ],
    );
  }
}

/// 左侧节次列：序号 + 该节的起止时刻（取自默认作息表）。
class _TimeColumn extends StatelessWidget {
  final int rows;
  final BellSchedule? bell;

  const _TimeColumn({required this.rows, required this.bell});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final byIndex = bell?.classByIndex ?? const <int, BellPeriod>{};
    return SizedBox(
      width: _timeColumnWidth,
      child: Column(
        children: [
          for (var r = 1; r <= rows; r++)
            SizedBox(
              height: _rowHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$r',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (byIndex[r] != null) ...[
                    Text(
                      hm(byIndex[r]!.start),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: TextStyle(fontSize: 9, color: scheme.outline),
                    ),
                    Text(
                      hm(byIndex[r]!.end),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: TextStyle(fontSize: 9, color: scheme.outline),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 一天的课程列：卡片按行区间绝对定位，重叠的课分轨道并排。
class _DayColumn extends StatelessWidget {
  final List<_Placed> placed;
  final bool isToday;
  final void Function(ResolvedLesson) onTapLesson;

  const _DayColumn({
    required this.placed,
    required this.isToday,
    required this.onTapLesson,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Stack(
          children: [
            if (isToday)
              Positioned.fill(
                child: ColoredBox(
                  color: scheme.primary.withValues(alpha: 0.05),
                ),
              ),
            for (final p in placed)
              Positioned(
                left: p.track * width / p.trackCount + 1,
                width: width / p.trackCount - 2,
                top: (p.startRow - 1) * _rowHeight + 1.5,
                height: (p.endRow - p.startRow + 1) * _rowHeight - 3,
                child: _LessonCard(
                  lesson: p.lesson,
                  compact: p.endRow == p.startRow,
                  onTap: () => onTapLesson(p.lesson),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LessonCard extends StatelessWidget {
  final ResolvedLesson lesson;

  /// 只占一行时收紧文字行数。
  final bool compact;
  final VoidCallback onTap;

  const _LessonCard({
    required this.lesson,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: lessonColor(lesson),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  lesson.subjectName,
                  maxLines: compact ? 2 : 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (lesson.room.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '@${lesson.room}',
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 10,
                      height: 1.2,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 网格线：每节次一条横线，每天一条竖线。
class _GridPainter extends CustomPainter {
  final int rows;
  final Color lineColor;

  const _GridPainter({required this.rows, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.5;
    for (var r = 1; r < rows; r++) {
      final y = r * _rowHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    final dayWidth = (size.width - _timeColumnWidth) / 7;
    for (var c = 0; c < 7; c++) {
      final x = _timeColumnWidth + c * dayWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      oldDelegate.rows != rows || oldDelegate.lineColor != lineColor;
}

// ---- 布局计算 ----

/// 已定位的一节课：占第 [startRow]–[endRow] 行（含），在重叠簇内排第
/// [track] 条轨道、共 [trackCount] 条。
class _Placed {
  final ResolvedLesson lesson;
  final int startRow;
  final int endRow;
  int track = 0;
  int trackCount = 1;

  _Placed(this.lesson, this.startRow, this.endRow);
}

int _clampInt(int v, int min, int max) => v < min ? min : (v > max ? max : v);

/// 左侧时刻列用的作息表：默认 → 周一指派 → 任意一张。
BellSchedule? _timeColumnBell(Calendar cal) {
  return cal.bellSchedules[cal.defaultBellScheduleId] ??
      cal.bellScheduleForWeekday(DateTime.monday) ??
      (cal.bellSchedules.isEmpty ? null : cal.bellSchedules.values.first);
}

/// 一节课占的行区间（行=节次序号）。
///
/// 自定义时刻的课（startPeriod=0）按与作息节次的时间重叠估算；完全落在
/// 网格外（如晚自习）时放到其后最近的节，再不行放最后一行。
(int, int) _rowRangeOf(ResolvedLesson lesson, BellSchedule? bell, int rows) {
  if (lesson.startPeriod >= 1) {
    final s = _clampInt(lesson.startPeriod, 1, rows);
    final rawEnd = lesson.endPeriod >= lesson.startPeriod
        ? lesson.endPeriod
        : lesson.startPeriod;
    return (s, _clampInt(rawEnd, s, rows));
  }
  final classes = (bell?.periods ?? const <BellPeriod>[])
      .where((p) => p.isClass)
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  int? first;
  int? last;
  for (final p in classes) {
    if (p.end > lesson.start && p.start < lesson.end) {
      first ??= p.index;
      last = p.index;
    }
  }
  if (first != null) {
    final s = _clampInt(first, 1, rows);
    return (s, _clampInt(last!, s, rows));
  }
  for (final p in classes) {
    if (p.start >= lesson.start) {
      final s = _clampInt(p.index, 1, rows);
      return (s, s);
    }
  }
  return (rows, rows);
}

/// 解析行区间并给重叠的课分轨道：按行聚成簇，簇内贪心取第一条空轨道，
/// 簇内所有课等分列宽。
List<_Placed> _layoutDay(
  List<ResolvedLesson> lessons,
  BellSchedule? bell,
  int rows,
) {
  final placed = <_Placed>[];
  for (final l in lessons) {
    final (s, e) = _rowRangeOf(l, bell, rows);
    placed.add(_Placed(l, s, e));
  }
  placed.sort((a, b) => a.startRow != b.startRow
      ? a.startRow - b.startRow
      : a.endRow - b.endRow);

  var i = 0;
  while (i < placed.length) {
    var j = i + 1;
    var maxEnd = placed[i].endRow;
    while (j < placed.length && placed[j].startRow <= maxEnd) {
      if (placed[j].endRow > maxEnd) maxEnd = placed[j].endRow;
      j++;
    }
    final trackEnds = <int>[]; // 每条轨道最后占到的行
    for (var k = i; k < j; k++) {
      final item = placed[k];
      var track = trackEnds.indexWhere((end) => end < item.startRow);
      if (track == -1) {
        trackEnds.add(item.endRow);
        track = trackEnds.length - 1;
      } else {
        trackEnds[track] = item.endRow;
      }
      item.track = track;
    }
    for (var k = i; k < j; k++) {
      placed[k].trackCount = trackEnds.length;
    }
    i = j;
  }
  return placed;
}
