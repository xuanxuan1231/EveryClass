import 'package:everyclass/app_state.dart';
import 'package:everyclass/data/database_repository.dart';
import 'package:everyclass/models/calendar.dart';
import 'package:everyclass/models/course_event.dart';
import 'package:everyclass/models/database.dart';
import 'package:everyclass/models/meeting.dart';
import 'package:everyclass/models/occurrence_override.dart';
import 'package:everyclass/services/settings_service.dart';
import 'package:everyclass/ui/schedule/course_edit_screen.dart';
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

/// 已有一门「语文」（周二 1-2 节，含一条停课调整）的数据库。
Database _populated() {
  const bell = AppState.defaultBellSchedule;
  const course = CourseEvent(
    id: 'c1',
    title: '语文',
    teacher: '李老师',
    meetings: [
      Meeting(
        id: 'm1',
        weekday: 2,
        startPeriod: 1,
        endPeriod: 2,
        overrides: {'2026-03-03': OccurrenceOverride(excluded: true)},
      ),
    ],
  );
  return Database(
    selectedCalendarId: 'cal',
    calendars: {
      'cal': Calendar(
        id: 'cal',
        name: '测试课表',
        bellSchedules: const {'bs-default': bell},
        defaultBellScheduleId: 'bs-default',
        courses: const {'c1': course},
      ),
    },
  );
}

/// 编辑页保存/删除后会 pop，故从宿主页 push 进入。
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
                child: const Text('打开编辑页'),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _open(WidgetTester tester, AppState app, Widget screen) async {
  await tester.pumpWidget(_host(app, screen));
  await tester.tap(find.text('打开编辑页'));
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

  // AppState 保存/删除后会经 MethodChannel 刷新常驻通知；widget 测试里该调用
  // 若无 handler 永不完成，会卡住后续的 Navigator.pop——必须 mock。
  const channel = MethodChannel('everyclass/live_notification');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => true);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('手动添加课程：名称 + 时段（默认星期来自入口）', (tester) async {
    final app = await _appWith(Database.empty());
    await _open(tester, app, const CourseEditScreen(initialWeekday: 3));

    await tester.enterText(find.byType(TextField).first, '高等数学');

    await _scrollTo(tester, find.text('添加时段'));
    await tester.tap(find.text('添加时段'));
    await tester.pumpAndSettle();

    // 入口星期（周三）已默认选中
    final chip =
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '周三'));
    expect(chip.selected, isTrue);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('周三 · 第 1 节'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('打开编辑页'), findsOneWidget); // 已 pop 回宿主

    final cal = app.calendar!;
    expect(cal.bellSchedules, isNotEmpty); // 自动创建的默认作息
    final course = cal.courses.values.single;
    expect(course.title, '高等数学');
    expect(course.meetings.single.weekday, 3);
    expect(course.meetings.single.startPeriod, 1);
    expect(app.hasSchedule, isTrue);
  });

  testWidgets('名称为空时保存被拦截', (tester) async {
    final app = await _appWith(Database.empty());
    await _open(tester, app, const CourseEditScreen());

    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(find.text('请填写课程名称'), findsOneWidget);
    expect(find.text('打开编辑页'), findsNothing); // 仍停留在编辑页
    expect(app.database.isEmpty, isTrue);
  });

  testWidgets('编辑课程：改名换星期，单次调整保留', (tester) async {
    final db = _populated();
    final app = await _appWith(db);
    final course = db.selected!.courses['c1']!;
    await _open(tester, app, CourseEditScreen(course: course));

    await tester.enterText(find.byType(TextField).first, '语文（下）');

    await _scrollTo(tester, find.text('周二 · 第 1-2 节'));
    await tester.tap(find.text('周二 · 第 1-2 节'));
    await tester.pumpAndSettle();
    expect(find.text('含 1 条单次调整，保存后保留'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '周五'));
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = app.calendar!.courses['c1']!;
    expect(saved.title, '语文（下）');
    final m = saved.meetings.single;
    expect(m.id, 'm1');
    expect(m.weekday, 5);
    expect(m.startPeriod, 1);
    expect(m.endPeriod, 2);
    expect(m.overrides['2026-03-03']!.excluded, isTrue);
  });

  testWidgets('编辑页可删除课程', (tester) async {
    final db = _populated();
    final app = await _appWith(db);
    await _open(
        tester, app, CourseEditScreen(course: db.selected!.courses['c1']));

    await tester.tap(find.byTooltip('删除课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(app.calendar!.courses, isEmpty);
    expect(find.text('打开编辑页'), findsOneWidget); // 已 pop 回宿主
  });

  testWidgets('周次选择：「增加周数」可排入 20 周以后（学期无 20 周上限）',
      (tester) async {
    final db = _populated();
    final app = await _appWith(db);
    final course = db.selected!.courses['c1']!;
    await _open(tester, app, CourseEditScreen(course: course));

    // 打开已有时段 → 周次选择对话框。
    await _scrollTo(tester, find.text('周二 · 第 1-2 节'));
    await tester.tap(find.text('周二 · 第 1-2 节'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('每周'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每周'));
    await tester.pumpAndSettle();

    // 默认网格 20 格，没有第 21 周。
    expect(find.widgetWithText(FilterChip, '20'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '21'), findsNothing);

    // 增加周数 → 网格扩到 25 格。
    await tester.ensureVisible(find.text('增加周数'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('增加周数'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, '25'), findsOneWidget);

    // 全选 1-25 并确定。
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    final dialogConfirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('确定'),
    );
    await tester.tap(dialogConfirm);
    await tester.pumpAndSettle();
    expect(find.text('第 1-25 周'), findsOneWidget);

    // 确定时段并保存课程。
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final cal = app.calendar!;
    final m = cal.courses['c1']!.meetings.single;
    expect(m.weeks.fromWeek, 1);
    expect(m.weeks.toWeek, 25);
    expect(cal.weekCount, 25); // 学期周数随排课推导，突破 20

    // 再次编辑：另一时段的网格以课表推导周数为起点（25 格）。
    await _open(tester, app, CourseEditScreen(course: cal.courses['c1']));
    await _scrollTo(tester, find.text('添加时段'));
    await tester.tap(find.text('添加时段'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('每周'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每周'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, '25'), findsOneWidget);
  });
}
