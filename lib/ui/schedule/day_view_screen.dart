import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/resolved_lesson.dart';
import '../../util/dates.dart';
import '../../util/format.dart';
import 'course_edit_screen.dart';
import 'empty_schedule_hint.dart';
import 'lesson_colors.dart';
import 'lesson_detail_sheet.dart';

/// 日视图：顶部周条 + 左右滑动翻天（PageView）。
///
/// 今天页保留原「今日课表」的能力：当前/下一节高亮卡与逐秒倒计时。
class DayViewScreen extends StatefulWidget {
  const DayViewScreen({super.key});

  @override
  State<DayViewScreen> createState() => DayViewScreenState();
}

class DayViewScreenState extends State<DayViewScreen> {
  late final PageController _pageController =
      PageController(initialPage: dayPageOf(DateTime.now()));
  DateTime _selected = dateOnly(DateTime.now());
  DateTime _now = DateTime.now();
  Timer? _timer;

  /// 跳回今天（供桌面卡片点课深链落地：切到日视图后确保停在今天页）。
  void jumpToToday() => _goTo(dateOnly(DateTime.now()));

  @override
  void initState() {
    super.initState();
    // 每秒刷新，驱动今天页的倒计时与当前节高亮。
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(DateTime day) {
    if (!_pageController.hasClients) return;
    final target = dayPageOf(day);
    // 跨度太大时直接跳页，避免长距离翻页动画。
    if ((target - dayPageOf(_selected)).abs() > 14) {
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
    final week = app.schedule?.weekOf(_selected);
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
        title: Text(
          week == null
              ? '${_selected.year}年${_selected.month}月'
              : '${_selected.year}年${_selected.month}月 · 第 $week 周',
        ),
        centerTitle: false,
        actions: [
          if (!isSameDay(_selected, _now))
            IconButton(
              tooltip: '回到今天',
              icon: const Icon(Icons.today_outlined),
              onPressed: () => _goTo(dateOnly(DateTime.now())),
            ),
          IconButton(
            tooltip: '添加课程',
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    CourseEditScreen(initialWeekday: _selected.weekday),
              ),
            ),
          ),
        ],
      ),
      body: !app.hasSchedule
          ? const EmptySchedulePlaceholder()
          : Column(
              children: [
                _WeekStrip(
                  selected: _selected,
                  today: dateOnly(_now),
                  onSelect: _goTo,
                ),
                const Divider(height: 1),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (page) =>
                        setState(() => _selected = dayFromPage(page)),
                    itemBuilder: (context, page) =>
                        _DayPage(app: app, day: dayFromPage(page), now: _now),
                  ),
                ),
              ],
            ),
    );
  }
}

/// 顶部周条：所选日期所在周的 7 天，点按跳转；随翻页跨周自动切换。
class _WeekStrip extends StatelessWidget {
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onSelect;

  const _WeekStrip({
    required this.selected,
    required this.today,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final monday = mondayOf(selected);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            _dayCell(
              context,
              DateTime(monday.year, monday.month, monday.day + i),
            ),
        ],
      ),
    );
  }

  Widget _dayCell(BuildContext context, DateTime day) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = isSameDay(day, selected);
    final isToday = isSameDay(day, today);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onSelect(day),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Text(
                weekdayShortCn(day),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color:
                          isToday ? scheme.primary : scheme.onSurfaceVariant,
                      fontWeight: isToday ? FontWeight.bold : null,
                    ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? scheme.primary : Colors.transparent,
                  shape: BoxShape.circle,
                  border: isToday && !isSelected
                      ? Border.all(color: scheme.primary)
                      : null,
                ),
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? scheme.onPrimary
                        : isToday
                            ? scheme.primary
                            : scheme.onSurface,
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

/// 一天的课表页。
class _DayPage extends StatelessWidget {
  final AppState app;
  final DateTime day;
  final DateTime now;

  const _DayPage({required this.app, required this.day, required this.now});

  @override
  Widget build(BuildContext context) {
    final lessons =
        app.schedule?.scheduleFor(day).lessons ?? const <ResolvedLesson>[];
    final isToday = isSameDay(day, now);

    ResolvedLesson? current;
    ResolvedLesson? next;
    if (isToday) {
      for (final l in lessons) {
        if (l.isCurrentAt(now)) current = l;
        if (next == null && l.startOn(now).isAfter(now)) next = l;
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _DayHeader(day: day, lessonCount: lessons.length),
        if (lessons.isEmpty) ...[
          const SizedBox(height: 96),
          Center(
            child: Icon(
              Icons.beach_access_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '这一天没有课',
              style:
                  TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        ] else ...[
          if (isToday) ...[
            const SizedBox(height: 12),
            _HighlightCard(now: now, current: current, next: next),
          ],
          const SizedBox(height: 16),
          for (final l in lessons)
            _LessonTile(
              lesson: l,
              isCurrent: identical(l, current),
              onTap: () => showLessonDetailSheet(
                context,
                lesson: l,
                day: day,
                course: app.calendar?.courses[l.subjectId],
              ),
            ),
        ],
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  final DateTime day;
  final int lessonCount;

  const _DayHeader({required this.day, required this.lessonCount});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${day.month}月${day.day}日 ${weekdayCn(day)}',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (lessonCount > 0)
          Text(
            '$lessonCount 节课',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
      ],
    );
  }
}

/// 当前/下一节高亮卡（含倒计时），仅今天页展示。
class _HighlightCard extends StatelessWidget {
  final DateTime now;
  final ResolvedLesson? current;
  final ResolvedLesson? next;

  const _HighlightCard({required this.now, this.current, this.next});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (current != null) {
      final remaining = current!.endOn(now).difference(now);
      return _bigCard(
        context,
        bg: scheme.primaryContainer,
        fg: scheme.onPrimaryContainer,
        tag: '正在进行',
        lesson: current!,
        trailingLabel: '距下课',
        trailingValue: fmtCountdown(remaining),
      );
    }
    if (next != null) {
      final until = next!.startOn(now).difference(now);
      return _bigCard(
        context,
        bg: scheme.secondaryContainer,
        fg: scheme.onSecondaryContainer,
        tag: '下一节',
        lesson: next!,
        trailingLabel: '距上课',
        trailingValue: fmtCountdown(until),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: scheme.primary),
            const SizedBox(width: 12),
            const Expanded(child: Text('今天的课都上完啦 🎉')),
          ],
        ),
      ),
    );
  }

  Widget _bigCard(
    BuildContext context, {
    required Color bg,
    required Color fg,
    required String tag,
    required ResolvedLesson lesson,
    required String trailingLabel,
    required String trailingValue,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tag, style: TextStyle(color: fg.withValues(alpha: 0.8))),
                const SizedBox(height: 6),
                Text(
                  lesson.subjectName,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: fg, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _iconLine(Icons.schedule,
                    '${hm(lesson.start)} - ${hm(lesson.end)}', fg),
                if (lesson.room.isNotEmpty)
                  _iconLine(Icons.location_on_outlined, lesson.room, fg),
                if (lesson.teacher.isNotEmpty)
                  _iconLine(Icons.person_outline, lesson.teacher, fg),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(trailingLabel,
                  style: TextStyle(color: fg.withValues(alpha: 0.8))),
              const SizedBox(height: 4),
              Text(
                trailingValue,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.bold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconLine(IconData icon, String text, Color fg) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg.withValues(alpha: 0.9)),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: fg)),
        ],
      ),
    );
  }
}

/// 单节课列表项：时间列 + 课程色条 + 名称/教师/教室 + 节次。
class _LessonTile extends StatelessWidget {
  final ResolvedLesson lesson;
  final bool isCurrent;
  final VoidCallback onTap;

  const _LessonTile({
    required this.lesson,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final periodLabel = lesson.startPeriod < 1
        ? ''
        : lesson.endPeriod > lesson.startPeriod
            ? '第 ${lesson.startPeriod}-${lesson.endPeriod} 节'
            : '第 ${lesson.startPeriod} 节';
    final subtitle = [
      if (lesson.room.isNotEmpty) lesson.room,
      if (lesson.teacher.isNotEmpty) lesson.teacher,
    ].join(' · ');

    return Card(
      elevation: isCurrent ? 2 : 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: isCurrent ? scheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Column(
                  children: [
                    Text(hm(lesson.start),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(hm(lesson.end),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Container(
                width: 4,
                height: 40,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: lessonColor(lesson),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lesson.subjectName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              if (periodLabel.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    periodLabel,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: scheme.outline),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
