import 'package:flutter/material.dart';

import 'course_edit_screen.dart';

/// 无课表时的占位提示（日/周视图共用）：可直接手动建课，或去设置导入。
class EmptySchedulePlaceholder extends StatelessWidget {
  const EmptySchedulePlaceholder({super.key});

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
              '手动添加课程，或到「设置」导入 ClassIsland 档案（.json）',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CourseEditScreen(),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('添加课程'),
            ),
          ],
        ),
      ),
    );
  }
}
