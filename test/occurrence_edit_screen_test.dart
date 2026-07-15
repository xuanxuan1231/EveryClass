import 'package:everyclass/app_state.dart';
import 'package:everyclass/data/database_repository.dart';
import 'package:everyclass/models/alert.dart';
import 'package:everyclass/models/calendar.dart';
import 'package:everyclass/models/course_event.dart';
import 'package:everyclass/models/database.dart';
import 'package:everyclass/models/meeting.dart';
import 'package:everyclass/models/occurrence_override.dart';
import 'package:everyclass/models/week_rule.dart';
import 'package:everyclass/services/settings_service.dart';
import 'package:everyclass/ui/schedule/course_edit_screen.dart';
import 'package:everyclass/ui/schedule/occurrence_edit_screen.dart';
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

/// 「语文」周二 1-2 节；含全套全局信息（教师/教室/备注/标签/提醒）。
/// 开学第 1 周周一 = 2026-03-02，第 2 周周二 = 2026-03-10。
Database _populated({Map<String, OccurrenceOverride> overrides = const {}}) {
  const bell = AppState.defaultBellSchedule;
  final course = CourseEvent(
    id: 'c1',
    title: '语文',
    teacher: '张老师',
    defaultLocation: '教三-201',
    description: '带计算器',
    keywords: const ['必修'],
    alerts: [Alert.beforeStart(const Duration(minutes: 5))],
    meetings: [
      Meeting(
        id: 'm1',
        weekday: 2,
        startPeriod: 1,
        endPeriod: 2,
        weeks: const WeekRule(fromWeek: 1, toWeek: 4),
        overrides: overrides,
      ),
    ],
  );
  return Database(
    selectedCalendarId: 'cal',
    calendars: {
      'cal': Calendar(
        id: 'cal',
        name: '测试课表',
        firstWeekStart: DateTime(2026, 3, 2),
        bellSchedules: const {'bs-default': bell},
        defaultBellScheduleId: 'bs-default',
        courses: {'c1': course},
      ),
    },
  );
}

Widget _host(AppState app, Widget screen) =>
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => screen),
                ),
                child: const Text('打开单次编辑'),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _open(WidgetTester tester, AppState app, Widget screen) async {
  await tester.pumpWidget(_host(app, screen));
  await tester.tap(find.text('打开单次编辑'));
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.dragUntilVisible(
    finder,
    find.byType(ListView),
    const Offset(0, -200),
  );
  await tester.pumpAndSettle();
}

OccurrenceEditScreen _screen() => OccurrenceEditScreen(
      courseId: 'c1',
      meetingId: 'm1',
      date: DateTime(2026, 3, 10),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('everyclass/live_notification');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => true);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('只读区展示除排课外的全局信息与「编辑课程」入口', (tester) async {
    final app = await _appWith(_populated());
    await _open(tester, app, _screen());

    expect(find.text('语文'), findsOneWidget);
    expect(find.text('默认教师'), findsOneWidget);
    expect(find.text('默认教室'), findsOneWidget);
    expect(find.text('默认备注'), findsOneWidget);
    expect(find.text('标签'), findsOneWidget);
    expect(find.text('必修'), findsOneWidget);
    expect(find.text('提醒'), findsOneWidget);
    expect(find.text('上课前 5 分钟'), findsOneWidget);
    expect(find.text('编辑课程'), findsOneWidget);
    // 只读区没有排课时段编辑入口
    expect(find.text('排课时段'), findsNothing);
    expect(find.text('添加时段'), findsNothing);
  });

  testWidgets('可编辑字段预填生效值（该日补丁优先于默认）', (tester) async {
    final app = await _appWith(_populated(overrides: const {
      '2026-03-10': OccurrenceOverride(teacher: '王老师'),
    }));
    await _open(tester, app, _screen());

    // 教师取该日补丁，教室/备注回落课程默认；字段靠下，逐个滚动到可见。
    await _scrollTo(tester, find.widgetWithText(TextField, '王老师'));
    expect(find.widgetWithText(TextField, '王老师'), findsOneWidget);
    await _scrollTo(tester, find.widgetWithText(TextField, '教三-201'));
    expect(find.widgetWithText(TextField, '教三-201'), findsOneWidget);
    await _scrollTo(tester, find.widgetWithText(TextField, '带计算器'));
    expect(find.widgetWithText(TextField, '带计算器'), findsOneWidget);
  });

  testWidgets('「编辑课程」跳到全局编辑页', (tester) async {
    final app = await _appWith(_populated());
    await _open(tester, app, _screen());

    await tester.tap(find.text('编辑课程'));
    await tester.pumpAndSettle();

    expect(find.byType(CourseEditScreen), findsOneWidget);
    expect(find.widgetWithText(TextField, '语文'), findsOneWidget);
  });

  testWidgets('改日期 → 仅本次调课 movedToDate', (tester) async {
    final app = await _appWith(_populated());
    await _open(tester, app, _screen());

    await tester.tap(find.text('2026-03-10 周二'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('12')); // 2026-03-12（周四）
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('2026-03-12 周四'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅修改本次'));
    await tester.pumpAndSettle();

    final m = app.calendar!.courses['c1']!.meetings.single;
    expect(m.weekday, 2); // 基础不变
    expect(m.overrides['2026-03-10']!.movedToDate, '2026-03-12');
  });

  testWidgets('课程不存在时自动返回', (tester) async {
    final app = await _appWith(_populated());
    await _open(
      tester,
      app,
      OccurrenceEditScreen(
        courseId: 'missing',
        meetingId: 'm1',
        date: DateTime(2026, 3, 10),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('打开单次编辑'), findsOneWidget);
  });
}
