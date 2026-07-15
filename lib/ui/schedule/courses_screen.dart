import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/course_event.dart';
import 'course_edit_screen.dart';
import 'course_icons.dart';
import 'lesson_colors.dart';

/// 课程管理：当前课表全部课程的列表，可新增、编辑、删除。
///
/// 与日/周视图不同，这里也能看到「暂无排课」的课程（它们不会出现在课表
/// 网格上），是手动维护课程信息的入口枢纽。
class CoursesScreen extends StatelessWidget {
  const CoursesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final courses = (app.calendar?.courses.values.toList() ?? <CourseEvent>[])
      ..sort((a, b) => a.title.compareTo(b.title));

    return Scaffold(
      appBar: AppBar(title: const Text('课程管理'), centerTitle: false),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('添加课程'),
      ),
      body: courses.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.school_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '还没有课程',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '点右下角「添加课程」手动创建，\n或到「设置」导入 ClassIsland 档案。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                for (final c in courses) _CourseTile(course: c),
              ],
            ),
    );
  }

  static void _openEditor(BuildContext context, [CourseEvent? course]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CourseEditScreen(course: course),
      ),
    );
  }
}

class _CourseTile extends StatelessWidget {
  final CourseEvent course;

  const _CourseTile({required this.course});

  @override
  Widget build(BuildContext context) {
    final color = courseDisplayColor(course.id, course.title, course.color);
    final icon = courseIcon(course.icon);
    final subtitle = [
      if (course.teacher.isNotEmpty) course.teacher,
      if (course.defaultLocation.isNotEmpty) course.defaultLocation,
      course.meetings.isEmpty ? '暂无排课' : '${course.meetings.length} 个时段',
    ].join(' · ');

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        child: icon != null
            ? Icon(icon, size: 20)
            : Text(
                course.title.isEmpty ? '?' : course.title.characters.first,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
      title: Text(course.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        tooltip: '删除课程',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _delete(context),
      ),
      onTap: () => CoursesScreen._openEditor(context, course),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final app = context.read<AppState>();
    if (!await confirmDeleteCourse(context, course.title)) return;
    await app.deleteCourse(course.id);
  }
}
