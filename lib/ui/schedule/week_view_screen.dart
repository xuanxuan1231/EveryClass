import 'dart:math' as math;

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

/// 竖轴比例：每分钟对应的像素高度（一节 40 分钟 ≈ 44px）。
const double _pxPerMinute = 1.1;
const double _timeColumnWidth = 52;

/// 网格顶/底留白，避免首节紧贴分隔线。
const double _vPad = 6;

/// 课程卡片的最小高度，保证极短的课也能显示文字。
const double _minCardHeight = 24;

/// 分钟坐标 → 竖轴像素（[gridStartMin] 为网格起始的当日分钟数）。
double _yFor(int minute, int gridStartMin) =>
    _vPad + (minute - gridStartMin) * _pxPerMinute;

/// 周视图：按真实时间比例排布的时间轴网格，左右滑动翻周（PageView）。
///
/// 竖轴=当日分钟（等比例），列=星期一至日；左列是作息表节次分区，每节按
/// 其起止时刻定位与定高，节次之间的空档（课间/午休）留出对应的空白。
/// 课程按自身真实起止时刻画成彩色卡片，未占满或超出所在节次都能正确显示，
/// 点按弹出详情。
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
        title: _AppBarTitle(week: week, monthLabel: monthLabel),
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

/// AppBar 标题：学期内显示「第 N 周 + 月份」，学期前只显示月份。
///
/// 两种状态切换时，月份文字在原位置与目标位置之间平移，并在大标题样式与
/// 次要小字样式之间插值，营造「同一块文字移动过去」的观感；周数文字淡入淡出。
class _AppBarTitle extends StatefulWidget {
  /// 本周在学期中的周数；学期前为 null。
  final int? week;
  final String monthLabel;

  const _AppBarTitle({required this.week, required this.monthLabel});

  @override
  State<_AppBarTitle> createState() => _AppBarTitleState();
}

class _AppBarTitleState extends State<_AppBarTitle>
    with SingleTickerProviderStateMixin {
  /// 0 = 学期前（仅月份），1 = 学期内（周数 + 月份）。
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: widget.week != null ? 1 : 0,
  );
  late final Animation<double> _t =
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic);

  /// 动画目标值，避免无关重建反复重启动画。
  late double _target = widget.week != null ? 1 : 0;

  /// 过渡期间仍需显示的周数：离开学期后 widget.week 变为 null，用它保留旧值。
  late int? _lastWeek = widget.week;

  @override
  void didUpdateWidget(_AppBarTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.week != null) _lastWeek = widget.week;
    final target = widget.week != null ? 1.0 : 0.0;
    if (target != _target) {
      _target = target;
      _controller.animateTo(target);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    // 大号样式取自 AppBar 注入的 DefaultTextStyle，保证学期前的月份与普通标题
    // 外观一致；小号样式沿用学期内的次要月份样式。
    final bigStyle = DefaultTextStyle.of(context).style;
    final smallStyle =
        theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.outline);
    const gap = 8.0;

    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final t = _t.value;
        final weekText = _lastWeek != null ? '第 $_lastWeek 周' : '';

        // 以大号月份确定整体行高与基线：月份始终非空，学期前后都稳定，标题块
        // 高度恒定，切换时不会上下跳动。
        final big = _measure(widget.monthLabel, bigStyle, scaler);
        final weekWidth =
            weekText.isEmpty ? 0.0 : _measure(weekText, bigStyle, scaler).width;

        final monthStyle = TextStyle.lerp(bigStyle, smallStyle, t)!;
        final month = _measure(widget.monthLabel, monthStyle, scaler);

        // 月份左缘：从 0（学期前）平移到「周数宽 + 间距」（学期内）。
        final monthLeft = t * (weekWidth + gap);
        // 基线对齐：月份缩小后仍坐在大标题基线上，看起来是从基线向上生长。
        final monthTop = big.baseline - month.baseline;
        final width = math.max(t > 0 ? weekWidth : 0.0, monthLeft + month.width);

        return SizedBox(
          width: width,
          height: big.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (t > 0)
                Positioned(
                  left: 0,
                  top: 0,
                  child: Opacity(
                    opacity: t.clamp(0.0, 1.0),
                    child: Text(weekText, maxLines: 1, style: bigStyle),
                  ),
                ),
              Positioned(
                left: monthLeft,
                top: monthTop,
                child: Text(widget.monthLabel, maxLines: 1, style: monthStyle),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 量出单行文字的宽、高与基线位置（用完即弃）。
  _TextMetrics _measure(String text, TextStyle style, TextScaler scaler) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final metrics = _TextMetrics(
      width: tp.width,
      height: tp.height,
      baseline: tp.computeDistanceToActualBaseline(TextBaseline.alphabetic),
    );
    tp.dispose();
    return metrics;
  }
}

/// 单行文字的几何量度。
class _TextMetrics {
  final double width;
  final double height;
  final double baseline;

  const _TextMetrics({
    required this.width,
    required this.height,
    required this.baseline,
  });
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
    final timeBell = _timeColumnBell(cal);
    final today = dateOnly(DateTime.now());
    // 左列节次分区取自时刻列作息表的上课格，按开始时刻排序。
    final classPeriods = <BellPeriod>[
      for (final p in (timeBell?.periods ?? const <BellPeriod>[]))
        if (p.isClass) p,
    ]..sort((a, b) => a.start.compareTo(b.start));

    final placedByDay = [
      for (final d in days) _layoutDay(svc.scheduleFor(d).lessons),
    ];

    // 竖轴时间窗：覆盖所有节次与本周全部课程，向整点取整以便画整点线。
    var minStart = 8 * 60;
    var maxEnd = 18 * 60;
    if (classPeriods.isNotEmpty) {
      minStart = classPeriods.first.start.inMinutes;
      maxEnd = classPeriods.first.end.inMinutes;
      for (final p in classPeriods) {
        if (p.start.inMinutes < minStart) minStart = p.start.inMinutes;
        if (p.end.inMinutes > maxEnd) maxEnd = p.end.inMinutes;
      }
    }
    for (final day in placedByDay) {
      for (final p in day) {
        if (p.startMin < minStart) minStart = p.startMin;
        if (p.endMin > maxEnd) maxEnd = p.endMin;
      }
    }
    final gridStartMin = (minStart ~/ 60) * 60;
    final gridEndMin = ((maxEnd + 59) ~/ 60) * 60;
    final totalHeight = (gridEndMin - gridStartMin) * _pxPerMinute + _vPad * 2;

    return Column(
      children: [
        _WeekHeader(
          days: days,
          today: today,
          week: svc.weekOf(monday),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            child: SizedBox(
              height: totalHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _GridPainter(
                        gridStartMin: gridStartMin,
                        gridEndMin: gridEndMin,
                        lineColor:
                            scheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TimeColumn(
                        classPeriods: classPeriods,
                        gridStartMin: gridStartMin,
                      ),
                      for (var i = 0; i < 7; i++)
                        Expanded(
                          child: _DayColumn(
                            placed: placedByDay[i],
                            gridStartMin: gridStartMin,
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

/// 表头：左侧学期周（仅数字，无周数则留空） + 7 天（星期单字 + 日，今天高亮）。
class _WeekHeader extends StatelessWidget {
  final List<DateTime> days;
  final DateTime today;

  /// 本周在学期中的 1-based 周数；未设开学日或开学前为 null（不显示）。
  final int? week;

  const _WeekHeader({
    required this.days,
    required this.today,
    required this.week,
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
                week != null ? '$week' : '',
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
            '${day.day}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isToday ? scheme.onPrimary : scheme.outline,
            ),
          ),
        ),
      ],
    );
  }
}

/// 左侧节次分区列：每个上课节次按其真实起止时刻定位与定高，节次间的空档
/// （课间/午休）自然留白。块内显示节次名 + 起止时刻。
class _TimeColumn extends StatelessWidget {
  final List<BellPeriod> classPeriods;
  final int gridStartMin;

  const _TimeColumn({required this.classPeriods, required this.gridStartMin});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: _timeColumnWidth,
      child: Stack(
        children: [
          for (final p in classPeriods)
            Positioned(
              left: 2,
              right: 2,
              top: _yFor(p.start.inMinutes, gridStartMin),
              height:
                  (p.end.inMinutes - p.start.inMinutes) * _pxPerMinute,
              child: _PeriodBlock(period: p, scheme: scheme),
            ),
        ],
      ),
    );
  }
}

/// 单个节次分区块。
class _PeriodBlock extends StatelessWidget {
  final BellPeriod period;
  final ColorScheme scheme;

  const _PeriodBlock({required this.period, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final label =
        period.label.isNotEmpty ? period.label : '第${period.index}节';
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.hardEdge,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          Text(
            hm(period.start),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: TextStyle(fontSize: 9, color: scheme.outline),
          ),
          Text(
            hm(period.end),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: TextStyle(fontSize: 9, color: scheme.outline),
          ),
        ],
      ),
    );
  }
}

/// 一天的课程列：卡片按真实起止时刻绝对定位，时间重叠的课分轨道并排。
class _DayColumn extends StatelessWidget {
  final List<_Placed> placed;
  final int gridStartMin;
  final bool isToday;
  final void Function(ResolvedLesson) onTapLesson;

  const _DayColumn({
    required this.placed,
    required this.gridStartMin,
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
                top: _yFor(p.startMin, gridStartMin) + 1.5,
                height: ((p.endMin - p.startMin) * _pxPerMinute - 3)
                    .clamp(_minCardHeight, double.infinity),
                child: _LessonCard(
                  lesson: p.lesson,
                  compact: (p.endMin - p.startMin) * _pxPerMinute < 48,
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

/// 网格线：每整点一条横线，每天一条竖线。
class _GridPainter extends CustomPainter {
  final int gridStartMin;
  final int gridEndMin;
  final Color lineColor;

  const _GridPainter({
    required this.gridStartMin,
    required this.gridEndMin,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.5;
    // 整点横线只画在右侧课程区，左侧节次列由分区块自己覆盖，不被线穿过。
    for (var m = gridStartMin; m <= gridEndMin; m += 60) {
      final y = _yFor(m, gridStartMin);
      canvas.drawLine(Offset(_timeColumnWidth, y), Offset(size.width, y), paint);
    }
    final dayWidth = (size.width - _timeColumnWidth) / 7;
    for (var c = 0; c < 7; c++) {
      final x = _timeColumnWidth + c * dayWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      oldDelegate.gridStartMin != gridStartMin ||
      oldDelegate.gridEndMin != gridEndMin ||
      oldDelegate.lineColor != lineColor;
}

// ---- 布局计算 ----

/// 已定位的一节课：占据 [startMin]–[endMin]（当日分钟），在时间重叠簇内排第
/// [track] 条轨道、共 [trackCount] 条。
class _Placed {
  final ResolvedLesson lesson;
  final int startMin;
  final int endMin;
  int track = 0;
  int trackCount = 1;

  _Placed(this.lesson, this.startMin, this.endMin);
}

/// 左侧时刻列用的作息表：默认 → 周一指派 → 任意一张。
BellSchedule? _timeColumnBell(Calendar cal) {
  return cal.bellSchedules[cal.defaultBellScheduleId] ??
      cal.bellScheduleForWeekday(DateTime.monday) ??
      (cal.bellSchedules.isEmpty ? null : cal.bellSchedules.values.first);
}

/// 按真实起止时刻定位课程，并给时间重叠的课分轨道：按重叠聚成簇，簇内贪心
/// 取第一条空轨道，簇内所有课等分列宽。相邻（首尾相接）不算重叠。
List<_Placed> _layoutDay(List<ResolvedLesson> lessons) {
  final placed = <_Placed>[];
  for (final l in lessons) {
    final s = l.start.inMinutes;
    final e = l.end.inMinutes;
    placed.add(_Placed(l, s, e > s ? e : s + 1));
  }
  placed.sort((a, b) => a.startMin != b.startMin
      ? a.startMin - b.startMin
      : a.endMin - b.endMin);

  var i = 0;
  while (i < placed.length) {
    var j = i + 1;
    var maxEnd = placed[i].endMin;
    // 严格小于：某课起点正好等于簇内最大终点时视为不重叠，另起一簇。
    while (j < placed.length && placed[j].startMin < maxEnd) {
      if (placed[j].endMin > maxEnd) maxEnd = placed[j].endMin;
      j++;
    }
    final trackEnds = <int>[]; // 每条轨道最后占到的分钟
    for (var k = i; k < j; k++) {
      final item = placed[k];
      var track = trackEnds.indexWhere((end) => end <= item.startMin);
      if (track == -1) {
        trackEnds.add(item.endMin);
        track = trackEnds.length - 1;
      } else {
        trackEnds[track] = item.endMin;
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
