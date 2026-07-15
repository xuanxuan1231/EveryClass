import 'package:everyclass/app_state.dart';
import 'package:everyclass/data/database_repository.dart';
import 'package:everyclass/models/calendar.dart';
import 'package:everyclass/models/course_event.dart';
import 'package:everyclass/models/database.dart';
import 'package:everyclass/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemRepo implements DatabaseRepository {
  Database? db;
  _MemRepo(this.db);
  @override
  Future<void> clear() async => db = null;
  @override
  Future<Database?> load() async => db;
  @override
  Future<void> save(Database value) async => db = value;
}

/// 结构取自真实 ClassIsland 档案（只有 Subjects 的空课表足够覆盖导入路径）。
const _profileJson = '''
{
  "Name": "一班课表",
  "TimeLayouts": {},
  "ClassPlans": {},
  "Subjects": {
    "97d0bf3f-137f-4f8a-87d6-ff387063bbd3": {"Name":"语文","Initial":"语","TeacherName":"","IsOutDoor":false,"AttachedObjects":{},"IsActive":false},
    "66d1c380-d292-46e1-86d5-d403e2a4f200": {"Name":"信息技术","Initial":"信","TeacherName":"","IsOutDoor":true,"AttachedObjects":{},"IsActive":false}
  }
}
''';

void main() {
  // AppState 变更后会经 MethodChannel 刷新常驻通知；测试环境未注册插件，
  // 需要绑定初始化后由 LiveNotification 静默吞掉 MissingPluginException。
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(AppState, _MemRepo)> createApp() async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsService.create();
    final repo = _MemRepo(null);
    return (AppState(repo, settings, Database.empty()), repo);
  }

  group('createCalendar', () {
    test('新建即选中：字段修剪/归一化、自带默认作息、已持久化', () async {
      final (app, repo) = await createApp();
      final cal = await app.createCalendar(
        name: ' 2026 春季学期 ',
        color: '#1E88E5',
        firstWeekStart: DateTime(2026, 3, 2, 14, 30), // 时刻应被丢弃
        note: ' 大二下 ',
      );

      expect(app.calendar!.id, cal.id);
      expect(cal.name, '2026 春季学期');
      expect(cal.color, '#1E88E5');
      expect(cal.note, '大二下');
      expect(cal.firstWeekStart, DateTime(2026, 3, 2));
      expect(cal.weekCount, Calendar.defaultWeekCount); // 尚无排课
      expect(cal.defaultBellScheduleId, 'bs-default');
      expect(cal.bellSchedules, isNotEmpty);

      final persisted = await repo.load();
      expect(persisted!.selectedCalendarId, cal.id);
      expect(persisted.calendars.containsKey(cal.id), isTrue);
    });

    test('连续新建：ID 互不相同，最新的成为使用中', () async {
      final (app, _) = await createApp();
      final a = await app.createCalendar(name: 'A');
      final b = await app.createCalendar(name: 'B');

      expect(a.id, isNot(b.id));
      expect(app.calendars.length, 2);
      expect(app.calendar!.id, b.id);
    });
  });

  group('selectCalendar', () {
    test('切换使用中的课表并持久化；未命中静默', () async {
      final (app, repo) = await createApp();
      final a = await app.createCalendar(name: 'A');
      await app.createCalendar(name: 'B');

      await app.selectCalendar(a.id);
      expect(app.calendar!.id, a.id);
      expect((await repo.load())!.selectedCalendarId, a.id);

      await app.selectCalendar('not-exist');
      expect(app.calendar!.id, a.id);
    });
  });

  group('updateCalendarInfo', () {
    test('可编辑未选中的课表，不影响使用中', () async {
      final (app, _) = await createApp();
      final a = await app.createCalendar(name: 'A');
      final b = await app.createCalendar(name: 'B'); // 选中 b

      await app.updateCalendarInfo(
        a.id,
        name: '甲',
        color: '#43A047',
        firstWeekStart: DateTime(2026, 9, 7),
        note: '下学期',
      );

      final edited = app.database.calendars[a.id]!;
      expect(edited.name, '甲');
      expect(edited.color, '#43A047');
      expect(edited.firstWeekStart, DateTime(2026, 9, 7));
      expect(edited.note, '下学期');
      expect(app.calendar!.id, b.id); // 使用中不变
    });

    test('clearFirstWeekStart 清除开始日期；未命中静默', () async {
      final (app, _) = await createApp();
      final a =
          await app.createCalendar(name: 'A', firstWeekStart: DateTime(2026, 3, 2));

      await app.updateCalendarInfo(a.id, clearFirstWeekStart: true);
      expect(app.database.calendars[a.id]!.firstWeekStart, isNull);

      await app.updateCalendarInfo('not-exist', name: 'X'); // 不抛异常
    });
  });

  group('deleteCalendar', () {
    test('删除未选中的：使用中不变', () async {
      final (app, _) = await createApp();
      final a = await app.createCalendar(name: 'A');
      final b = await app.createCalendar(name: 'B');

      await app.deleteCalendar(a.id);
      expect(app.calendars.length, 1);
      expect(app.calendar!.id, b.id);
    });

    test('删除使用中的：改选剩余的第一张并持久化', () async {
      final (app, repo) = await createApp();
      final a = await app.createCalendar(name: 'A');
      final b = await app.createCalendar(name: 'B'); // 选中 b

      await app.deleteCalendar(b.id);
      expect(app.calendar!.id, a.id);
      expect((await repo.load())!.selectedCalendarId, a.id);
    });

    test('删除最后一张：回到无课表状态', () async {
      final (app, _) = await createApp();
      final a = await app.createCalendar(name: 'A');

      await app.deleteCalendar(a.id);
      expect(app.database.isEmpty, isTrue);
      expect(app.calendar, isNull);
      expect(app.hasSchedule, isFalse);

      await app.deleteCalendar(a.id); // 再删不抛异常
    });
  });

  group('importFromText（多课表语义）', () {
    test('导入新增一张课表并选中，原有课表保留', () async {
      final (app, _) = await createApp();
      final manual = await app.createCalendar(name: '手动课表');

      await app.importFromText(_profileJson);

      expect(app.calendars.length, 2);
      final imported = app.calendar!;
      expect(imported.id, isNot(manual.id));
      expect(imported.name, '一班课表');
      expect(imported.courses.length, 2);
      expect(app.database.calendars.containsKey(manual.id), isTrue);
    });

    test('再次导入同一档案：又新增一张，ID 不冲突', () async {
      final (app, _) = await createApp();
      await app.importFromText(_profileJson);
      final first = app.calendar!;
      await app.importFromText(_profileJson);

      expect(app.calendars.length, 2);
      expect(app.calendar!.id, isNot(first.id));
    });

    test('按标题从上一张使用中的课表带过走班教室，并继承开始日期', () async {
      final (app, _) = await createApp();
      await app.createCalendar(
        name: '旧学期',
        firstWeekStart: DateTime(2026, 3, 2),
      );
      await app.upsertCourse(const CourseEvent(
        id: 'old-chinese',
        title: '语文',
        defaultLocation: '教三-201',
      ));

      await app.importFromText(_profileJson);

      final imported = app.calendar!;
      expect(imported.name, '一班课表');
      final chinese = imported.courses.values
          .singleWhere((c) => c.title == '语文');
      expect(chinese.defaultLocation, '教三-201');
      expect(imported.firstWeekStart, DateTime(2026, 3, 2));
    });
  });
}
