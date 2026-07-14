import 'package:everyclass/app_state.dart';
import 'package:everyclass/data/database_repository.dart';
import 'package:everyclass/models/calendar.dart';
import 'package:everyclass/models/course_event.dart';
import 'package:everyclass/models/database.dart';
import 'package:everyclass/models/meeting.dart';
import 'package:everyclass/services/settings_service.dart';
import 'package:everyclass/ui/schedule/course_edit_screen.dart';
import 'package:everyclass/ui/schedule/courses_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      child: const MaterialApp(home: CoursesScreen()),
    );

Database _populated() {
  const bell = AppState.defaultBellSchedule;
  return Database(
    selectedCalendarId: 'cal',
    calendars: {
      'cal': Calendar(
        id: 'cal',
        bellSchedules: const {'bs-default': bell},
        defaultBellScheduleId: 'bs-default',
        courses: const {
          'c1': CourseEvent(
            id: 'c1',
            title: '数学',
            teacher: '李老师',
            meetings: [
              Meeting(id: 'm1', weekday: 1, startPeriod: 1, endPeriod: 2),
            ],
          ),
          'c2': CourseEvent(id: 'c2', title: '语文'),
        },
      ),
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 删除课程会经 MethodChannel 刷新常驻通知，widget 测试需 mock 才能完成调用。
  const channel = MethodChannel('everyclass/live_notification');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => true);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('列出全部课程（含暂无排课的）', (tester) async {
    final app = await _appWith(_populated());
    await tester.pumpWidget(_wrap(app));

    expect(find.text('数学'), findsOneWidget);
    expect(find.text('语文'), findsOneWidget);
    expect(find.textContaining('1 个时段'), findsOneWidget);
    expect(find.textContaining('暂无排课'), findsOneWidget);
  });

  testWidgets('删除课程需确认', (tester) async {
    final app = await _appWith(_populated());
    await tester.pumpWidget(_wrap(app));

    // 列表按标题排序：数学在前，删第一个
    await tester.tap(find.byTooltip('删除课程').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('「数学」'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(app.calendar!.courses.keys, ['c2']);
    expect(find.text('数学'), findsNothing);
    expect(find.text('语文'), findsOneWidget);
  });

  testWidgets('FAB 打开添加课程编辑页；点课程进入编辑', (tester) async {
    final app = await _appWith(_populated());
    await tester.pumpWidget(_wrap(app));

    await tester.tap(find.text('添加课程'));
    await tester.pumpAndSettle();
    expect(find.byType(CourseEditScreen), findsOneWidget);
    expect(find.text('添加课程'), findsOneWidget); // AppBar 标题

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('数学'));
    await tester.pumpAndSettle();
    expect(find.byType(CourseEditScreen), findsOneWidget);
    expect(find.text('编辑课程'), findsOneWidget);
  });

  testWidgets('空库显示占位提示', (tester) async {
    final app = await _appWith(Database.empty());
    await tester.pumpWidget(_wrap(app));
    expect(find.text('还没有课程'), findsOneWidget);
  });
}
