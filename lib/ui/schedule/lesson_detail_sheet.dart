import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/course_event.dart';
import '../../models/resolved_lesson.dart';
import '../../util/format.dart';
import 'course_edit_screen.dart';
import 'lesson_colors.dart';
import 'occurrence_edit_screen.dart';

/// 点击课程卡片后的详情底部弹层（日/周视图共用）。
///
/// [course] 可选：传入时补充展示标签（`ResolvedLesson` 里没有），并提供
/// 「编辑 / 删除课程」入口。「编辑」进单次编辑页 [OccurrenceEditScreen]（只调
/// 整这一次）；无法定位到具体时段时回退到课程全局编辑页 [CourseEditScreen]。
Future<void> showLessonDetailSheet(
  BuildContext context, {
  required ResolvedLesson lesson,
  required DateTime day,
  CourseEvent? course,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final periodLabel = lesson.startPeriod < 1
          ? ''
          : lesson.endPeriod > lesson.startPeriod
          ? '第 ${lesson.startPeriod} - ${lesson.endPeriod} 节'
          : '第 ${lesson.startPeriod} 节';
      final rows = <(IconData, String)>[
        (
          Icons.schedule_outlined,
          '${ymd(day)} ${weekdayCn(day)} · ${hm(lesson.start)} - ${hm(lesson.end)}',
        ),
        if (periodLabel.isNotEmpty) (Icons.format_list_numbered, periodLabel),
        if (lesson.room.isNotEmpty) (Icons.location_on_outlined, lesson.room),
        if (lesson.teacher.isNotEmpty) (Icons.person_outline, lesson.teacher),
        if (lesson.description.isNotEmpty)
          (Icons.notes_outlined, lesson.description),
      ];
      return SafeArea(
        child: ConstrainedBox(
          // 内容随例外/备注变长，限高并允许滚动，避免小屏溢出。
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: lessonColor(lesson),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        lesson.subjectName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                for (final (icon, text) in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          icon,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(text, style: theme.textTheme.bodyLarge),
                        ),
                      ],
                    ),
                  ),
                if (course != null && course.keywords.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final k in course.keywords)
                          Chip(
                            label: Text(k),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ),
                if (course != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('编辑'),
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _openEditor(context, course, lesson, day);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                          ),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('删除课程'),
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _confirmAndDelete(context, course);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// 「编辑」入口：能定位到这次课所属的时段则进单次编辑页；否则（meetingId
/// 缺失或时段已被删）回退到课程全局编辑页。
void _openEditor(
  BuildContext context,
  CourseEvent course,
  ResolvedLesson lesson,
  DateTime day,
) {
  final hasMeeting = lesson.meetingId.isNotEmpty &&
      course.meetings.any((m) => m.id == lesson.meetingId);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => hasMeeting
          ? OccurrenceEditScreen(
              courseId: course.id,
              meetingId: lesson.meetingId,
              date: lesson.originDate.isEmpty
                  ? day
                  : DateTime.tryParse(lesson.originDate) ?? day,
            )
          : CourseEditScreen(course: course),
    ),
  );
}

Future<void> _confirmAndDelete(BuildContext context, CourseEvent course) async {
  final app = context.read<AppState>();
  if (!await confirmDeleteCourse(context, course.title)) return;
  await app.deleteCourse(course.id);
}
