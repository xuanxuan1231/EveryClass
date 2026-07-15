import 'package:everyclass/app_state.dart';
import 'package:everyclass/data/classisland_importer.dart';
import 'package:everyclass/data/database_repository.dart';
import 'package:everyclass/models/database.dart';
import 'package:everyclass/services/settings_service.dart';
import 'package:everyclass/ui/schedule/week_view_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 周一到周日每天都有一节「语文」，一周恰好 7 张课程卡。
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
      child: const MaterialApp(home: WeekViewScreen()),
    );

DateTime _mondayOfThisWeek() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - (now.weekday - 1));
}

void main() {
  testWidgets('空数据库显示导入提示', (tester) async {
    final app = await _appWith(Database.empty());
    await tester.pumpWidget(_wrap(app));
    await tester.pumpAndSettle();
    expect(find.text('还没有课表'), findsOneWidget);
  });

  testWidgets('渲染整周课程与周序号', (tester) async {
    final app = await _appWith(
      ClassIslandImporter.parse(_populated,
          firstWeekStart: _mondayOfThisWeek()),
    );
    await tester.pumpWidget(_wrap(app));
    await tester.pumpAndSettle();
    expect(find.text('第 1 周'), findsOneWidget);
    expect(find.text('语文'), findsNWidgets(7));
  });

  testWidgets('左滑翻到下一周', (tester) async {
    final app = await _appWith(
      ClassIslandImporter.parse(_populated,
          firstWeekStart: _mondayOfThisWeek()),
    );
    await tester.pumpWidget(_wrap(app));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('第 2 周'), findsOneWidget);
    expect(find.text('语文'), findsNWidgets(7));
  });
}
