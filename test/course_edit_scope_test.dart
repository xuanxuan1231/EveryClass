import 'package:everyclass/app_state.dart';
import 'package:everyclass/data/database_repository.dart';
import 'package:everyclass/models/calendar.dart';
import 'package:everyclass/models/course_event.dart';
import 'package:everyclass/models/database.dart';
import 'package:everyclass/models/meeting.dart';
import 'package:everyclass/models/week_rule.dart';
import 'package:everyclass/services/settings_service.dart';
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

/// 「语文」周二 1-2 节、第 1-4 周；开学第 1 周周一 = 2026-03-02。
/// 第 2 周周二 = 2026-03-10。
Database _populated() {
  const bell = AppState.defaultBellSchedule;
  const course = CourseEvent(
    id: 'c1',
    title: '语文',
    teacher: '张老师',
    meetings: [
      Meeting(
        id: 'm1',
        weekday: 2,
        startPeriod: 1,
        endPeriod: 2,
        weeks: WeekRule(fromWeek: 1, toWeek: 4),
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
        courses: const {'c1': course},
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

  testWidgets('改教师保存 → 弹范围；选「仅修改本次」写补丁', (tester) async {
    final db = _populated();
    final app = await _appWith(db);
    await _open(
      tester,
      app,
      OccurrenceEditScreen(
        courseId: 'c1',
        meetingId: 'm1',
        date: DateTime(2026, 3, 10),
      ),
    );

    await _scrollTo(tester, find.widgetWithText(TextField, '本次教师'));
    await tester.enterText(find.widgetWithText(TextField, '本次教师'), '王老师');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('应用到哪些课？'), findsOneWidget);
    expect(find.text('修改本次及以后'), findsOneWidget);
    await tester.tap(find.text('仅修改本次'));
    await tester.pumpAndSettle();

    expect(find.text('打开单次编辑'), findsOneWidget); // 已保存并 pop
    final m = app.calendar!.courses['c1']!.meetings.single;
    expect(m.teacher, isNull); // 基础不变
    expect(m.overrides['2026-03-10']!.teacher, '王老师');
  });

  testWidgets('选「修改本次及以后」拆分时段', (tester) async {
    final db = _populated();
    final app = await _appWith(db);
    await _open(
      tester,
      app,
      OccurrenceEditScreen(
        courseId: 'c1',
        meetingId: 'm1',
        date: DateTime(2026, 3, 10),
      ),
    );

    await _scrollTo(tester, find.widgetWithText(TextField, '本次教师'));
    await tester.enterText(find.widgetWithText(TextField, '本次教师'), '王老师');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改本次及以后'));
    await tester.pumpAndSettle();

    final meetings = app.calendar!.courses['c1']!.meetings;
    expect(meetings, hasLength(2));
    final past = meetings.firstWhere((m) => m.weeks.matches(1));
    final future = meetings.firstWhere((m) => m.weeks.matches(2));
    expect(past.teacher, isNull);
    expect(past.weeks.matches(2), isFalse);
    expect(future.teacher, '王老师');
    expect(future.weeks.matches(4), isTrue);
  });

  testWidgets('只改本次备注：不弹范围，直接写 description override',
      (tester) async {
    final db = _populated();
    final app = await _appWith(db);
    await _open(
      tester,
      app,
      OccurrenceEditScreen(
        courseId: 'c1',
        meetingId: 'm1',
        date: DateTime(2026, 3, 10),
      ),
    );

    await _scrollTo(tester, find.widgetWithText(TextField, '只对这一次课生效'));
    await tester.enterText(
        find.widgetWithText(TextField, '只对这一次课生效'), '今天测验');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('应用到哪些课？'), findsNothing);
    expect(find.text('打开单次编辑'), findsOneWidget);
    final m = app.calendar!.courses['c1']!.meetings.single;
    expect(m.overrides['2026-03-10']!.description, '今天测验');
  });

  testWidgets('本次停课写 excluded', (tester) async {
    final db = _populated();
    final app = await _appWith(db);
    await _open(
      tester,
      app,
      OccurrenceEditScreen(
        courseId: 'c1',
        meetingId: 'm1',
        date: DateTime(2026, 3, 10),
      ),
    );

    await _scrollTo(tester, find.text('本次停课'));
    await tester.tap(find.text('本次停课'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '停课'));
    await tester.pumpAndSettle();

    final m = app.calendar!.courses['c1']!.meetings.single;
    expect(m.overrides['2026-03-10']!.excluded, isTrue);
  });

  testWidgets('无改动保存直接 pop', (tester) async {
    final db = _populated();
    final app = await _appWith(db);
    await _open(
      tester,
      app,
      OccurrenceEditScreen(
        courseId: 'c1',
        meetingId: 'm1',
        date: DateTime(2026, 3, 10),
      ),
    );

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('打开单次编辑'), findsOneWidget);
    expect(app.calendar!.courses['c1']!.meetings.single.overrides, isEmpty);
  });
}
