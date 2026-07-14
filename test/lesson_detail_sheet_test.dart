import 'package:everyclass/app_state.dart';
import 'package:everyclass/data/database_repository.dart';
import 'package:everyclass/models/calendar.dart';
import 'package:everyclass/models/course_event.dart';
import 'package:everyclass/models/database.dart';
import 'package:everyclass/models/meeting.dart';
import 'package:everyclass/models/resolved_lesson.dart';
import 'package:everyclass/services/settings_service.dart';
import 'package:everyclass/ui/schedule/course_edit_screen.dart';
import 'package:everyclass/ui/schedule/lesson_detail_sheet.dart';
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

const _course = CourseEvent(
  id: 'c1',
  title: '数学',
  description: '带计算器',
  keywords: ['必修'],
  meetings: [Meeting(id: 'm1', weekday: 1, startPeriod: 1, endPeriod: 1)],
);

/// 2026-07-13 是周一，与 m1 的 weekday 一致。
const _lesson = ResolvedLesson(
  subjectId: 'c1',
  subjectName: '数学',
  teacher: '李老师',
  room: 'A101',
  start: Duration(hours: 8),
  end: Duration(hours: 8, minutes: 45),
  period: 1,
  startPeriod: 1,
  endPeriod: 1,
  description: '带计算器',
  meetingId: 'm1',
  originDate: '2026-07-13',
);

Future<AppState> _appWith(Database db) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await SettingsService.create();
  return AppState(_MemRepo(db), settings, db);
}

Database _populated() {
  const bell = AppState.defaultBellSchedule;
  return Database(
    selectedCalendarId: 'cal',
    calendars: {
      'cal': Calendar(
        id: 'cal',
        bellSchedules: const {'bs-default': bell},
        defaultBellScheduleId: 'bs-default',
        courses: const {'c1': _course},
      ),
    },
  );
}

Widget _host(AppState app, {ResolvedLesson lesson = _lesson}) =>
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showLessonDetailSheet(
                  context,
                  lesson: lesson,
                  day: DateTime(2026, 7, 13),
                  course: _course,
                ),
                child: const Text('打开详情'),
              ),
            ),
          ),
        ),
      ),
    );

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

  testWidgets('详情弹层展示课程信息与编辑/删除入口', (tester) async {
    final app = await _appWith(_populated());
    await tester.pumpWidget(_host(app));
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();

    expect(find.text('数学'), findsOneWidget);
    expect(find.text('带计算器'), findsOneWidget); // 来自 lesson.description
    expect(find.text('必修'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('删除课程'), findsOneWidget);
  });

  testWidgets('「编辑」进入单次编辑页', (tester) async {
    final app = await _appWith(_populated());
    await tester.pumpWidget(_host(app));
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    expect(find.byType(OccurrenceEditScreen), findsOneWidget);
    expect(find.text('编辑本次'), findsOneWidget);
  });

  testWidgets('定位不到时段（meetingId 为空）时回退到全局编辑页',
      (tester) async {
    const legacy = ResolvedLesson(
      subjectId: 'c1',
      subjectName: '数学',
      teacher: '李老师',
      room: 'A101',
      start: Duration(hours: 8),
      end: Duration(hours: 8, minutes: 45),
      period: 1,
    );
    final app = await _appWith(_populated());
    await tester.pumpWidget(_host(app, lesson: legacy));
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    expect(find.byType(CourseEditScreen), findsOneWidget);
    expect(find.widgetWithText(TextField, '数学'), findsOneWidget);
  });

  testWidgets('「删除课程」确认后删除', (tester) async {
    final app = await _appWith(_populated());
    await tester.pumpWidget(_host(app));
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('删除课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(app.calendar!.courses, isEmpty);
  });
}
