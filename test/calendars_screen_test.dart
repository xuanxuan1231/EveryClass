import 'package:everyclass/app_state.dart';
import 'package:everyclass/data/database_repository.dart';
import 'package:everyclass/models/calendar.dart';
import 'package:everyclass/models/course_event.dart';
import 'package:everyclass/models/database.dart';
import 'package:everyclass/models/meeting.dart';
import 'package:everyclass/models/week_rule.dart';
import 'package:everyclass/services/settings_service.dart';
import 'package:everyclass/ui/schedule/calendar_edit_screen.dart';
import 'package:everyclass/ui/schedule/calendars_screen.dart';
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

/// 两张课表：使用中的「春季」（有一门 1-16 周的课，设了开始日期与备注）和
/// 备用的「秋季」（空）。
Database _twoCalendars() {
  const bell = AppState.defaultBellSchedule;
  final spring = Calendar(
    id: 'cal-spring',
    name: '春季',
    color: '#1E88E5',
    note: '大二下',
    firstWeekStart: DateTime(2026, 3, 2),
    bellSchedules: const {'bs-default': bell},
    defaultBellScheduleId: 'bs-default',
    courses: const {
      'c1': CourseEvent(
        id: 'c1',
        title: '数学',
        meetings: [
          Meeting(
            id: 'm1',
            weekday: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: WeekRule(fromWeek: 1, toWeek: 16),
          ),
        ],
      ),
    },
  );
  const autumn = Calendar(id: 'cal-autumn', name: '秋季');
  return Database(
    selectedCalendarId: 'cal-spring',
    calendars: {'cal-spring': spring, 'cal-autumn': autumn},
  );
}

Widget _wrap(AppState app) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: const MaterialApp(home: CalendarsScreen()),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // AppState 保存后会经 MethodChannel 刷新常驻通知；widget 测试里该调用
  // 若无 handler 永不完成，会卡住后续导航——必须 mock。
  const channel = MethodChannel('everyclass/live_notification');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => true);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('列出全部课表：概要含开学日期/周数/课程数，使用中的高亮', (tester) async {
    final app = await _appWith(_twoCalendars());
    await tester.pumpWidget(_wrap(app));

    expect(find.text('春季'), findsOneWidget);
    expect(find.text('秋季'), findsOneWidget);
    expect(find.text('2026-03-02 开学 · 16 周 · 1 门课程'), findsOneWidget);
    expect(find.text('未设开始日期 · 20 周 · 0 门课程'), findsOneWidget);
    expect(find.text('大二下'), findsOneWidget);

    final springTile =
        tester.widget<ListTile>(find.widgetWithText(ListTile, '春季'));
    final autumnTile =
        tester.widget<ListTile>(find.widgetWithText(ListTile, '秋季'));
    expect(springTile.selected, isTrue);
    expect(autumnTile.selected, isFalse);
  });

  testWidgets('点按切换使用中的课表', (tester) async {
    final app = await _appWith(_twoCalendars());
    await tester.pumpWidget(_wrap(app));

    await tester.tap(find.text('秋季'));
    await tester.pumpAndSettle();

    expect(app.calendar!.id, 'cal-autumn');
    final autumnTile =
        tester.widget<ListTile>(find.widgetWithText(ListTile, '秋季'));
    expect(autumnTile.selected, isTrue);
  });

  testWidgets('空态提示新建或导入', (tester) async {
    final app = await _appWith(Database.empty());
    await tester.pumpWidget(_wrap(app));

    expect(find.text('还没有课表'), findsOneWidget);
    expect(find.text('新建课表'), findsOneWidget); // FAB
  });

  testWidgets('FAB 新建：名称必填，保存后新课表出现并成为使用中', (tester) async {
    final app = await _appWith(Database.empty());
    await tester.pumpWidget(_wrap(app));

    await tester.tap(find.text('新建课表'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarEditScreen), findsOneWidget);
    expect(find.text('20 周'), findsOneWidget); // 周数只读展示默认值

    // 名称为空被拦截
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('请填写课表名称'), findsOneWidget);
    expect(app.database.isEmpty, isTrue);

    await tester.enterText(find.byType(TextField).first, '2026 春季学期');
    await tester.enterText(find.byType(TextField).last, '大二下');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.byType(CalendarEditScreen), findsNothing); // 已 pop 回列表
    expect(find.text('2026 春季学期'), findsOneWidget);
    final cal = app.calendar!;
    expect(cal.name, '2026 春季学期');
    expect(cal.note, '大二下');
    expect(cal.bellSchedules, isNotEmpty); // 可直接手动添加课程
  });

  testWidgets('编辑课表：修改名称与备注', (tester) async {
    final app = await _appWith(_twoCalendars());
    await tester.pumpWidget(_wrap(app));

    // 秋季 tile 上的编辑按钮（列表顺序：春季在前）
    await tester.tap(find.byTooltip('编辑课表').last);
    await tester.pumpAndSettle();
    expect(find.byType(CalendarEditScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '秋季（改）');
    await tester.enterText(find.byType(TextField).last, '备用');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final edited = app.database.calendars['cal-autumn']!;
    expect(edited.name, '秋季（改）');
    expect(edited.note, '备用');
    expect(app.calendar!.id, 'cal-spring'); // 使用中不变
  });

  testWidgets('编辑页展示按排课推导的周数', (tester) async {
    final app = await _appWith(_twoCalendars());
    await tester.pumpWidget(_wrap(app));

    await tester.tap(find.byTooltip('编辑课表').first); // 春季
    await tester.pumpAndSettle();

    expect(find.text('16 周'), findsOneWidget);
    expect(find.text('按课程排课的周次自动计算，不可手动修改'), findsOneWidget);
  });

  testWidgets('删除课表需确认；删除使用中的自动改选剩余', (tester) async {
    final app = await _appWith(_twoCalendars());
    await tester.pumpWidget(_wrap(app));

    await tester.tap(find.byTooltip('编辑课表').first); // 春季（使用中）
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除课表'));
    await tester.pumpAndSettle();

    // 取消不删
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(app.calendars.length, 2);

    await tester.tap(find.byTooltip('删除课表'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.byType(CalendarEditScreen), findsNothing); // 已 pop 回列表
    expect(app.calendars.length, 1);
    expect(app.calendar!.id, 'cal-autumn');
    expect(find.text('秋季'), findsOneWidget);
  });
}
