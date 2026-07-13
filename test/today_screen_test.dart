import 'package:everyclass/app_state.dart';
import 'package:everyclass/data/classisland_importer.dart';
import 'package:everyclass/data/database_repository.dart';
import 'package:everyclass/models/database.dart';
import 'package:everyclass/services/settings_service.dart';
import 'package:everyclass/ui/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _populated = '''
{
  "Subjects": {"s":{"Name":"语文","AttachedObjects":{"everyclass.room":"A101"}}},
  "TimeLayouts": {"t":{"Name":"t","Layouts":[{"StartTime":"08:00:00","EndTime":"08:45:00","TimeType":0}]}},
  "ClassPlans": {"p":{"Name":"周一","TimeLayoutId":"t","TimeRule":{"WeekDay":1,"WeekCountDiv":0},"Classes":[{"SubjectId":"s"}],"IsEnabled":true}}
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
      child: const MaterialApp(home: TodayScreen()),
    );

void main() {
  testWidgets('空数据库显示导入提示', (tester) async {
    final app = await _appWith(Database.empty());
    await tester.pumpWidget(_wrap(app));
    await tester.pump();
    expect(find.text('还没有课表'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // 释放周期性 Timer
  });

  testWidgets('有课表渲染今日页且不崩溃', (tester) async {
    final app = await _appWith(ClassIslandImporter.parse(_populated));
    await tester.pumpWidget(_wrap(app));
    await tester.pump();
    expect(find.text('今日课表'), findsOneWidget);
    expect(find.text('还没有课表'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
