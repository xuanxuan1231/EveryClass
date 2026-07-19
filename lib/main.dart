import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'models/resolved_lesson.dart';
import 'platform/live_notification.dart';
import 'platform/widget_deeplink.dart';
import 'ui/schedule/calendars_screen.dart';
import 'ui/schedule/courses_screen.dart';
import 'ui/schedule/day_view_screen.dart';
import 'ui/schedule/lesson_detail_sheet.dart';
import 'ui/schedule/week_view_screen.dart';
import 'ui/settings_screen.dart';
import 'util/dates.dart';

const notificationDemoEnabled = bool.fromEnvironment(
  'EVERYCLASS_NOTIFICATION_DEMO',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = await AppState.create();
  runApp(EveryClassApp(appState: appState));
  if (notificationDemoEnabled) {
    await LiveNotification.runDemo();
  }
}

class EveryClassApp extends StatelessWidget {
  final AppState appState;

  const EveryClassApp({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: MaterialApp(
        title: 'EveryClass',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        home: const HomeShell(),
      ),
    );
  }
}

/// 主壳：侧边导航用抽屉（[Drawer]）——默认隐藏，菜单键或左缘滑动打开后
/// 浮在页面上方；抽屉上部切换日/周视图，底部「设置」以二级页面推入。
///
/// 视图装在 [IndexedStack] 里，切换时保留各自的翻页位置与滚动状态。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  // 日视图需持有 key：桌面卡片点课深链落地时，切到日视图后要命令它跳回今天。
  final GlobalKey<DayViewScreenState> _dayViewKey =
      GlobalKey<DayViewScreenState>();
  late final List<Widget> _pages = [
    DayViewScreen(key: _dayViewKey),
    const WeekViewScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // 应用已在前台时的点课（热启动路径）。
    WidgetDeepLink.setListener(_handleDeepLink);
    // 由卡片点课冷启动应用时，取出那次点课并处理（等首帧后，确保课表已就绪、
    // Navigator 可用）。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final pending = await WidgetDeepLink.initialLesson();
      if (pending != null) _handleDeepLink(pending);
    });
  }

  /// 处理桌面卡片点课深链：先卸掉压在课表之上的一切（设置、课表/课程管理、
  /// 「编辑课程」「编辑本次」等编辑页、已打开的对话框与底部浮窗），回到主壳，
  /// 再切到日视图今天页并唤出这节课的详情浮窗。
  ///
  /// 「先回主壳」是关键：应用原先若停在编辑页或其它二级页，直接弹浮窗会叠在错误
  /// 页面之上、甚至压在正在编辑的课程表单上；popUntil 到根路由可一并收掉这些页面
  /// 与任何开着的浮窗/对话框。编辑页未保存的改动按应用既有的「返回即丢弃」处理。
  void _handleDeepLink(PendingLesson pending) {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _index = 0);
    // 等 IndexedStack 切换与页面构建完成后再跳今天、弹浮窗。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _dayViewKey.currentState?.jumpToToday();
      _openLessonSheet(pending);
    });
  }

  /// 在当天已解析课表里定位这节课并唤出详情浮窗；课程已变更/不存在则只停在今天页。
  void _openLessonSheet(PendingLesson pending) {
    final app = context.read<AppState>();
    final schedule = app.schedule;
    if (schedule == null) return;
    final today = dateOnly(DateTime.now());
    final lesson = _matchLesson(schedule.scheduleFor(today).lessons, pending);
    if (lesson == null) return;
    showLessonDetailSheet(
      context,
      lesson: lesson,
      day: today,
      course: app.calendar?.courses[lesson.subjectId],
    );
  }

  /// 按课程 ID + 起始分钟定位；走班可能同一时刻多节，故 ID 优先，再退回时刻匹配。
  ResolvedLesson? _matchLesson(
    List<ResolvedLesson> lessons,
    PendingLesson pending,
  ) {
    ResolvedLesson? byStart;
    for (final l in lessons) {
      final sameStart = l.start.inMinutes == pending.startMinute;
      if (pending.subjectId.isNotEmpty &&
          l.subjectId == pending.subjectId &&
          sameStart) {
        return l;
      }
      if (sameStart) byStart ??= l;
    }
    if (pending.subjectId.isNotEmpty) {
      for (final l in lessons) {
        if (l.subjectId == pending.subjectId) return l;
      }
    }
    return byStart;
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  void _openCalendars() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CalendarsScreen()),
    );
  }

  void _openCourses() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CoursesScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _AppDrawer(
        selectedIndex: _index,
        onSelectView: (i) => setState(() => _index = i),
        onOpenCalendars: _openCalendars,
        onOpenCourses: _openCourses,
        onOpenSettings: _openSettings,
      ),
      body: IndexedStack(index: _index, children: _pages),
    );
  }
}

/// 侧边导航抽屉：上部日/周视图，底部「课表管理」「课程管理」与「设置」。
/// 点按任意项先收起抽屉。
class _AppDrawer extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectView;
  final VoidCallback onOpenCalendars;
  final VoidCallback onOpenCourses;
  final VoidCallback onOpenSettings;

  const _AppDrawer({
    required this.selectedIndex,
    required this.onSelectView,
    required this.onOpenCalendars,
    required this.onOpenCourses,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
              child: Text(
                'EveryClass',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
            _DrawerItem(
              icon: Icons.calendar_view_day_outlined,
              selectedIcon: Icons.calendar_view_day,
              label: '日视图',
              selected: selectedIndex == 0,
              onTap: () {
                Navigator.pop(context);
                onSelectView(0);
              },
            ),
            _DrawerItem(
              icon: Icons.calendar_view_week_outlined,
              selectedIcon: Icons.calendar_view_week,
              label: '周视图',
              selected: selectedIndex == 1,
              onTap: () {
                Navigator.pop(context);
                onSelectView(1);
              },
            ),
            const Spacer(),
            const Divider(height: 1, indent: 28, endIndent: 28),
            const SizedBox(height: 8),
            _DrawerItem(
              icon: Icons.calendar_month_outlined,
              selectedIcon: Icons.calendar_month,
              label: '课表管理',
              selected: false,
              onTap: () {
                Navigator.pop(context);
                onOpenCalendars();
              },
            ),
            _DrawerItem(
              icon: Icons.school_outlined,
              selectedIcon: Icons.school,
              label: '课程管理',
              selected: false,
              onTap: () {
                Navigator.pop(context);
                onOpenCourses();
              },
            ),
            _DrawerItem(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
              label: '设置',
              selected: false,
              onTap: () {
                Navigator.pop(context);
                onOpenSettings();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// M3 风格抽屉项：胶囊指示器 + 图标 + 标签。
class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        leading: Icon(selected ? selectedIcon : icon),
        title: Text(label),
        selected: selected,
        selectedTileColor: scheme.secondaryContainer,
        selectedColor: scheme.onSecondaryContainer,
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        shape: const StadiumBorder(),
        onTap: onTap,
      ),
    );
  }
}
