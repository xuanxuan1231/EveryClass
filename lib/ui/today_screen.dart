import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/resolved_lesson.dart';
import '../util/format.dart';

/// 今日课表：时间轴 + 当前/下一节高亮 + 倒计时。
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // 每秒刷新，驱动倒计时与当前节高亮。
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final now = _now;
    final svc = app.schedule;
    final day = svc?.scheduleFor(now);

    ResolvedLesson? current;
    ResolvedLesson? next;
    if (day != null) {
      for (final l in day.lessons) {
        if (l.isCurrentAt(now)) current = l;
        if (next == null && l.startOn(now).isAfter(now)) next = l;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('今日课表'),
        centerTitle: false,
      ),
      body: !app.hasSchedule || day == null
          ? const _EmptyImportHint()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _DateHeader(now: now, weekNumber: app.weekNumber),
                const SizedBox(height: 12),
                _HighlightCard(now: now, current: current, next: next),
                const SizedBox(height: 20),
                if (day.lessons.isNotEmpty)
                  Text('今日安排', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final l in day.lessons)
                  _LessonTile(lesson: l, isCurrent: identical(l, current)),
              ],
            ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  final DateTime now;
  final int? weekNumber;
  const _DateHeader({required this.now, required this.weekNumber});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      ymd(now),
      weekdayCn(now),
      if (weekNumber != null) '第 $weekNumber 周',
    ];
    return Text(
      parts.join('  ·  '),
      style: Theme.of(context)
          .textTheme
          .titleLarge
          ?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

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
        tag: '正在上课',
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

class _LessonTile extends StatelessWidget {
  final ResolvedLesson lesson;
  final bool isCurrent;
  const _LessonTile({required this.lesson, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: isCurrent ? 2 : 0,
      color: isCurrent ? scheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 52,
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
              width: 1,
              height: 36,
              color: scheme.outlineVariant,
              margin: const EdgeInsets.symmetric(horizontal: 12),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${lesson.period}. ${lesson.subjectName}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  if (lesson.teacher.isNotEmpty)
                    Text(lesson.teacher,
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (lesson.room.isNotEmpty)
              Chip(
                label: Text(lesson.room),
                avatar: const Icon(Icons.location_on_outlined, size: 16),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyImportHint extends StatelessWidget {
  const _EmptyImportHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_note_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            const Text(
              '还没有课表',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '到「设置」导入 ClassIsland 档案（.json）',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
