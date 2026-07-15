import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'platform/live_notification.dart';
import 'ui/schedule/calendars_screen.dart';
import 'ui/schedule/courses_screen.dart';
import 'ui/schedule/day_view_screen.dart';
import 'ui/schedule/week_view_screen.dart';
import 'ui/settings_screen.dart';

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

  static const _pages = [DayViewScreen(), WeekViewScreen()];

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
