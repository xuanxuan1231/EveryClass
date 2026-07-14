import 'package:everyclass/app_state.dart';
import 'package:everyclass/data/database_repository.dart';
import 'package:everyclass/models/course_event.dart';
import 'package:everyclass/models/database.dart';
import 'package:everyclass/models/meeting.dart';
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

  test('upsertCourse：空库自动建默认课表（含默认作息）并持久化', () async {
    final (app, repo) = await createApp();
    await app.upsertCourse(CourseEvent(
      id: 'c1',
      title: '数学',
      meetings: [
        const Meeting(id: 'm1', weekday: 1, startPeriod: 1, endPeriod: 2),
      ],
    ));

    final cal = app.calendar;
    expect(cal, isNotNull);
    expect(cal!.bellSchedules.containsKey('bs-default'), isTrue);
    expect(cal.defaultBellScheduleId, 'bs-default');
    expect(cal.courses['c1']!.title, '数学');
    expect(app.hasSchedule, isTrue);

    // 已写入仓库
    final persisted = await repo.load();
    expect(persisted!.selected!.courses.containsKey('c1'), isTrue);
  });

  test('upsertCourse：同 ID 整体替换', () async {
    final (app, _) = await createApp();
    await app.upsertCourse(const CourseEvent(id: 'c1', title: '数学'));
    await app.upsertCourse(const CourseEvent(id: 'c1', title: '高等数学'));
    expect(app.calendar!.courses.length, 1);
    expect(app.calendar!.courses['c1']!.title, '高等数学');
  });

  test('deleteCourse：删除指定课程，未命中时静默', () async {
    final (app, repo) = await createApp();
    await app.upsertCourse(const CourseEvent(id: 'c1', title: '数学'));
    await app.upsertCourse(const CourseEvent(id: 'c2', title: '语文'));

    await app.deleteCourse('c1');
    expect(app.calendar!.courses.keys, ['c2']);
    expect((await repo.load())!.selected!.courses.keys, ['c2']);

    await app.deleteCourse('not-exist'); // 不抛异常
    expect(app.calendar!.courses.length, 1);
  });

  test('手动课程经默认作息解析出正确时刻（2026-07-13 为周一）', () async {
    final (app, _) = await createApp();
    await app.upsertCourse(CourseEvent(
      id: 'c1',
      title: '数学',
      meetings: [
        const Meeting(id: 'm1', weekday: 1, startPeriod: 1, endPeriod: 2),
      ],
    ));

    final lessons =
        app.schedule!.scheduleFor(DateTime(2026, 7, 13)).lessons;
    expect(lessons, hasLength(1));
    expect(lessons.first.subjectName, '数学');
    expect(lessons.first.start, const Duration(hours: 8));
    expect(lessons.first.end, const Duration(hours: 9, minutes: 40));

    // 周二无课
    expect(app.schedule!.scheduleFor(DateTime(2026, 7, 14)).lessons, isEmpty);
  });

  test('自定义时刻的时段不依赖作息表即可解析', () async {
    final (app, _) = await createApp();
    await app.upsertCourse(CourseEvent(
      id: 'c1',
      title: '晚自习',
      meetings: [
        const Meeting(
          id: 'm1',
          weekday: 1,
          customStart: '19:00',
          customEnd: '20:30',
        ),
      ],
    ));

    final lessons =
        app.schedule!.scheduleFor(DateTime(2026, 7, 13)).lessons;
    expect(lessons, hasLength(1));
    expect(lessons.first.start, const Duration(hours: 19));
    expect(lessons.first.end, const Duration(hours: 20, minutes: 30));
    expect(lessons.first.startPeriod, 0);
  });
}
