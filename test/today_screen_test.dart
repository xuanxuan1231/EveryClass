import 'package:everyclass/app_state.dart';
import 'package:everyclass/data/classisland_importer.dart';
import 'package:everyclass/data/profile_repository.dart';
import 'package:everyclass/models/profile.dart';
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

class _MemRepo implements ProfileRepository {
  Profile? _p;
  _MemRepo(this._p);
  @override
  Future<void> clear() async => _p = null;
  @override
  Future<Profile?> load() async => _p;
  @override
  Future<void> save(Profile profile) async => _p = profile;
}

Future<AppState> _appWith(Profile p) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await SettingsService.create();
  return AppState(_MemRepo(p), settings, p);
}

Widget _wrap(AppState app) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: const MaterialApp(home: TodayScreen()),
    );

void main() {
  testWidgets('空档案显示导入提示', (tester) async {
    final app = await _appWith(Profile.empty());
    await tester.pumpWidget(_wrap(app));
    await tester.pump();
    expect(find.text('还没有课表'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // 释放周期性 Timer
  });

  testWidgets('有档案渲染今日页且不崩溃', (tester) async {
    final app = await _appWith(ClassIslandImporter.parse(_populated));
    await tester.pumpWidget(_wrap(app));
    await tester.pump();
    expect(find.text('今日课表'), findsOneWidget);
    expect(find.text('还没有课表'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
