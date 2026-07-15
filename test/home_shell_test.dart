import 'package:everyclass/app_state.dart';
import 'package:everyclass/data/database_repository.dart';
import 'package:everyclass/main.dart';
import 'package:everyclass/models/database.dart';
import 'package:everyclass/services/settings_service.dart';
import 'package:everyclass/ui/schedule/calendars_screen.dart';
import 'package:everyclass/ui/schedule/courses_screen.dart';
import 'package:everyclass/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemRepo implements DatabaseRepository {
  Database? _db;
  _MemRepo(this._db);
  @override
  Future<void> clear() async => _db = null;
  @override
  Future<Database?> load() async => _db;
  @override
  Future<void> save(Database db) async => _db = db;
}

Future<AppState> _appWith(Database db) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await SettingsService.create();
  return AppState(_MemRepo(db), settings, db);
}

Widget _wrap(AppState app) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: const MaterialApp(home: HomeShell()),
    );

/// 日/周两页的 AppBar 都在 IndexedStack 里（各有一个菜单键），
/// 用 hitTestable 只取当前可见页的那个。
Finder get _menuButton => find.byIcon(Icons.menu).hitTestable();

void main() {
  // 日视图内的 Timer 是 1 秒一跳，pumpAndSettle 会在两跳之间收敛，可放心使用；
  // 测试结尾仍需 pumpWidget(SizedBox) 释放 Timer。

  testWidgets('抽屉默认隐藏，菜单键打开', (tester) async {
    final app = await _appWith(Database.empty());
    await tester.pumpWidget(_wrap(app));
    await tester.pump();

    // 抽屉收起时不在树上，导航项不可见。
    expect(find.text('日视图'), findsNothing);
    await tester.tap(_menuButton);
    await tester.pumpAndSettle();
    expect(find.text('日视图'), findsOneWidget);
    expect(find.text('周视图'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // 释放周期性 Timer
  });

  testWidgets('抽屉切换周视图后自动收起', (tester) async {
    final app = await _appWith(Database.empty());
    await tester.pumpWidget(_wrap(app));
    await tester.pump();

    await tester.tap(_menuButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('周视图'));
    await tester.pumpAndSettle();
    // 抽屉已收起。
    expect(find.text('周视图'), findsNothing);

    // 重新打开，验证「周视图」为选中态。
    await tester.tap(_menuButton);
    await tester.pumpAndSettle();
    final tile =
        tester.widget<ListTile>(find.widgetWithText(ListTile, '周视图'));
    expect(tile.selected, isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('课程管理以二级页面推入', (tester) async {
    final app = await _appWith(Database.empty());
    await tester.pumpWidget(_wrap(app));
    await tester.pump();

    await tester.tap(_menuButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('课程管理'));
    await tester.pumpAndSettle();
    expect(find.byType(CoursesScreen), findsOneWidget);
    expect(find.text('还没有课程'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('课表管理以二级页面推入', (tester) async {
    final app = await _appWith(Database.empty());
    await tester.pumpWidget(_wrap(app));
    await tester.pump();

    await tester.tap(_menuButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('课表管理'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarsScreen), findsOneWidget);
    expect(find.text('还没有课表'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('设置以二级页面推入并可返回', (tester) async {
    final app = await _appWith(Database.empty());
    await tester.pumpWidget(_wrap(app));
    await tester.pump();

    await tester.tap(_menuButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('导入 ClassIsland 档案'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
    // 返回后抽屉保持收起。
    expect(find.text('日视图'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
