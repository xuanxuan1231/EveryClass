import 'package:everyclass/app_state.dart';
import 'package:everyclass/data/classisland_importer.dart';
import 'package:everyclass/data/database_repository.dart';
import 'package:everyclass/models/database.dart';
import 'package:everyclass/services/settings_service.dart';
import 'package:everyclass/ui/schedule/day_view_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 周一到周日每天都有一节「语文」，保证无论今天周几都能渲染出课程。
final _populated = '''
{
  "Subjects": {"s":{"Name":"语文","AttachedObjects":{"everyclass.room":"A101"}}},
  "TimeLayouts": {"t":{"Name":"t","Layouts":[{"StartTime":"08:00:00","EndTime":"08:45:00","TimeType":0}]}},
  "ClassPlans": {${[
  for (var w = 1; w <= 7; w++)
    '"p$w":{"Name":"d$w","TimeLayoutId":"t","TimeRule":{"WeekDay":$w,"WeekCountDiv":0},"Classes":[{"SubjectId":"s"}],"IsEnabled":true}'
].join(',')}}
}
''';

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
      child: const MaterialApp(home: DayViewScreen()),
    );

void main() {
  testWidgets('空数据库显示导入提示', (tester) async {
    final app = await _appWith(Database.empty());
    await tester.pumpWidget(_wrap(app));
    await tester.pump();
    expect(find.text('还没有课表'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // 释放周期性 Timer
  });

  testWidgets('渲染今天的课程', (tester) async {
    final app = await _appWith(ClassIslandImporter.parse(_populated));
    await tester.pumpWidget(_wrap(app));
    await tester.pump();
    expect(find.text('语文'), findsWidgets);
    expect(find.text('还没有课表'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('左滑翻到明天', (tester) async {
    final app = await _appWith(ClassIslandImporter.parse(_populated));
    await tester.pumpWidget(_wrap(app));
    await tester.pump();

    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      find.textContaining('${tomorrow.month}月${tomorrow.day}日'),
      findsOneWidget,
    );
    expect(find.text('语文'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
}
