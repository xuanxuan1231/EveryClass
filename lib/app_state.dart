import 'package:flutter/foundation.dart';

import 'data/classisland_importer.dart';
import 'data/database_repository.dart';
import 'data/local_database_repository.dart';
import 'models/bell_schedule.dart';
import 'models/calendar.dart';
import 'models/course_event.dart';
import 'models/database.dart';
import 'platform/live_notification.dart';
import 'services/schedule_service.dart';
import 'services/settings_service.dart';
import 'util/local_id.dart';

/// 应用级状态：持有数据库与设置，暴露导入/教室/学期/通知等操作，变更后驱动 UI
/// 与通知刷新。
class AppState extends ChangeNotifier {
  final DatabaseRepository _repo;
  final SettingsService settings;
  Database _db;

  AppState(this._repo, this.settings, this._db);

  static Future<AppState> create() async {
    final repo = LocalDatabaseRepository();
    final settings = await SettingsService.create();
    final db = await repo.load() ?? Database.empty();
    final state = AppState(repo, settings, db);
    await state._refreshNotification();
    return state;
  }

  Database get database => _db;

  /// 当前选中的学期课表；无则 null。
  Calendar? get calendar => _db.selected;

  /// 全部课表（创建/导入顺序）。
  List<Calendar> get calendars => _db.calendars.values.toList();

  ScheduleService? get schedule {
    final cal = calendar;
    return cal == null ? null : ScheduleService(cal);
  }

  /// 是否已有可用课表（有作息且有课程排课）。
  bool get hasSchedule {
    final cal = calendar;
    if (cal == null) return false;
    if (cal.bellSchedules.isEmpty) return false;
    return cal.courses.values.any((c) => c.meetings.isNotEmpty);
  }

  /// 当前是学期第几周（未设 firstWeekStart 则为 null）。
  int? get weekNumber {
    final now = DateTime.now();
    return schedule?.weekOf(now);
  }

  /// 学期第一周所在日期（存于选中 Calendar）。
  DateTime? get firstWeekStart => calendar?.firstWeekStart;

  /// 导入 ClassIsland 档案文本，作为一张**新课表**加入并选中（已有课表保持
  /// 不变）；抛出的 [ImportException] 由调用方展示。
  Future<void> importFromText(String jsonText) async {
    final imported = ClassIslandImporter.parse(
      jsonText,
      calendarId: _newCalendarId(),
      firstWeekStart: firstWeekStart,
    );
    var cal = imported.selected;
    if (cal == null) return;
    cal = _mergeRooms(cal, calendar);
    _db = _db.withCalendar(cal).copyWith(selectedCalendarId: cal.id);
    await _repo.save(_db);
    notifyListeners();
    await _refreshNotification();
  }

  // ---- 课表管理 ----

  /// 生成不与现有课表冲突的新 ID（时间戳粒度不足时加序号）。
  String _newCalendarId() {
    final base = newLocalId('cal');
    var id = base;
    var n = 2;
    while (_db.calendars.containsKey(id)) {
      id = '$base-${n++}';
    }
    return id;
  }

  /// 新建一张空课表（含默认作息，可直接手动添加课程）并选中，返回新课表。
  Future<Calendar> createCalendar({
    required String name,
    String color = '',
    DateTime? firstWeekStart,
    String note = '',
  }) async {
    final cal = Calendar(
      id: _newCalendarId(),
      name: name.trim(),
      color: color,
      note: note.trim(),
      firstWeekStart: _dateOnly(firstWeekStart),
      bellSchedules: const {'bs-default': defaultBellSchedule},
      defaultBellScheduleId: defaultBellSchedule.id,
    );
    _db = _db.withCalendar(cal).copyWith(selectedCalendarId: cal.id);
    await _repo.save(_db);
    notifyListeners();
    await _refreshNotification();
    return cal;
  }

  /// 编辑任意一张课表的基本信息（名称/颜色/开始日期/备注）；周数由课程排课
  /// 自动推导（[Calendar.weekCount]），不在此列。未命中 [id] 时静默。
  Future<void> updateCalendarInfo(
    String id, {
    String? name,
    String? color,
    DateTime? firstWeekStart,
    bool clearFirstWeekStart = false,
    String? note,
  }) async {
    final cal = _db.calendars[id];
    if (cal == null) return;
    _db = _db.withCalendar(cal.copyWith(
      name: name?.trim(),
      color: color,
      note: note?.trim(),
      firstWeekStart: _dateOnly(firstWeekStart),
      clearFirstWeekStart: clearFirstWeekStart,
    ));
    await _repo.save(_db);
    notifyListeners();
    await _refreshNotification();
  }

  /// 删除一张课表（连同其全部课程与排课）；删的是选中项时自动改选剩余的
  /// 第一张。未命中时静默。
  Future<void> deleteCalendar(String id) async {
    if (!_db.calendars.containsKey(id)) return;
    _db = _db.withoutCalendar(id);
    await _repo.save(_db);
    notifyListeners();
    await _refreshNotification();
  }

  /// 切换正在使用的课表。未命中或已选中时静默。
  Future<void> selectCalendar(String id) async {
    if (!_db.calendars.containsKey(id)) return;
    if (_db.selectedCalendarId == id) return;
    _db = _db.copyWith(selectedCalendarId: id);
    await _repo.save(_db);
    notifyListeners();
    await _refreshNotification();
  }

  static DateTime? _dateOnly(DateTime? day) =>
      day == null ? null : DateTime(day.year, day.month, day.day);

  /// 手动建课时的默认作息：8 节课 + 课间/午休。仅在数据库还没有任何课表时
  /// 随默认课表一起创建；导入档案会整体替换，不受影响。
  static const BellSchedule defaultBellSchedule = BellSchedule(
    id: 'bs-default',
    name: '默认作息',
    periods: [
      BellPeriod(
        index: 1,
        kind: BellPeriodKind.klass,
        start: Duration(hours: 8),
        end: Duration(hours: 8, minutes: 45),
        label: '第1节',
      ),
      BellPeriod(
        index: 0,
        kind: BellPeriodKind.breakTime,
        start: Duration(hours: 8, minutes: 45),
        end: Duration(hours: 8, minutes: 55),
      ),
      BellPeriod(
        index: 2,
        kind: BellPeriodKind.klass,
        start: Duration(hours: 8, minutes: 55),
        end: Duration(hours: 9, minutes: 40),
        label: '第2节',
      ),
      BellPeriod(
        index: 0,
        kind: BellPeriodKind.breakTime,
        start: Duration(hours: 9, minutes: 40),
        end: Duration(hours: 10, minutes: 10),
      ),
      BellPeriod(
        index: 3,
        kind: BellPeriodKind.klass,
        start: Duration(hours: 10, minutes: 10),
        end: Duration(hours: 10, minutes: 55),
        label: '第3节',
      ),
      BellPeriod(
        index: 0,
        kind: BellPeriodKind.breakTime,
        start: Duration(hours: 10, minutes: 55),
        end: Duration(hours: 11, minutes: 5),
      ),
      BellPeriod(
        index: 4,
        kind: BellPeriodKind.klass,
        start: Duration(hours: 11, minutes: 5),
        end: Duration(hours: 11, minutes: 50),
        label: '第4节',
      ),
      BellPeriod(
        index: 0,
        kind: BellPeriodKind.lunch,
        start: Duration(hours: 11, minutes: 50),
        end: Duration(hours: 14),
      ),
      BellPeriod(
        index: 5,
        kind: BellPeriodKind.klass,
        start: Duration(hours: 14),
        end: Duration(hours: 14, minutes: 45),
        label: '第5节',
      ),
      BellPeriod(
        index: 0,
        kind: BellPeriodKind.breakTime,
        start: Duration(hours: 14, minutes: 45),
        end: Duration(hours: 14, minutes: 55),
      ),
      BellPeriod(
        index: 6,
        kind: BellPeriodKind.klass,
        start: Duration(hours: 14, minutes: 55),
        end: Duration(hours: 15, minutes: 40),
        label: '第6节',
      ),
      BellPeriod(
        index: 0,
        kind: BellPeriodKind.breakTime,
        start: Duration(hours: 15, minutes: 40),
        end: Duration(hours: 16),
      ),
      BellPeriod(
        index: 7,
        kind: BellPeriodKind.klass,
        start: Duration(hours: 16),
        end: Duration(hours: 16, minutes: 45),
        label: '第7节',
      ),
      BellPeriod(
        index: 0,
        kind: BellPeriodKind.breakTime,
        start: Duration(hours: 16, minutes: 45),
        end: Duration(hours: 16, minutes: 55),
      ),
      BellPeriod(
        index: 8,
        kind: BellPeriodKind.klass,
        start: Duration(hours: 16, minutes: 55),
        end: Duration(hours: 17, minutes: 40),
        label: '第8节',
      ),
    ],
  );

  /// 手动建课前确保有课表可写：没有任何课表时，建一张含 [defaultBellSchedule]
  /// 的「我的课表」并选中。
  Calendar _ensureCalendar() {
    final existing = calendar;
    if (existing != null) return existing;
    final cal = Calendar(
      id: 'cal-manual',
      name: '我的课表',
      bellSchedules: const {'bs-default': defaultBellSchedule},
      defaultBellScheduleId: defaultBellSchedule.id,
    );
    _db = _db.withCalendar(cal);
    return cal;
  }

  /// 新增或整体替换一门课程（含其全部排课时段）。
  Future<void> upsertCourse(CourseEvent course) async {
    final cal = _ensureCalendar();
    final courses = Map<String, CourseEvent>.from(cal.courses);
    courses[course.id] = course;
    _db = _db.withCalendar(cal.copyWith(courses: courses));
    await _repo.save(_db);
    notifyListeners();
    await _refreshNotification();
  }

  /// 删除一门课程（连同其全部排课时段与单次例外）。
  Future<void> deleteCourse(String courseId) async {
    final cal = calendar;
    if (cal == null || !cal.courses.containsKey(courseId)) return;
    final courses = Map<String, CourseEvent>.from(cal.courses)
      ..remove(courseId);
    _db = _db.withCalendar(cal.copyWith(courses: courses));
    await _repo.save(_db);
    notifyListeners();
    await _refreshNotification();
  }

  /// 设置某门课的默认教室（走班场景）。
  Future<void> setCourseRoom(String courseId, String room) async {
    final cal = calendar;
    if (cal == null) return;
    final course = cal.courses[courseId];
    if (course == null) return;
    final courses = Map<String, CourseEvent>.from(cal.courses);
    courses[courseId] = course.copyWith(defaultLocation: room.trim());
    _db = _db.withCalendar(cal.copyWith(courses: courses));
    await _repo.save(_db);
    notifyListeners();
    await _refreshNotification();
  }

  Future<void> setEnhancedCountdown(bool value) async {
    await settings.setEnhancedCountdown(value);
    notifyListeners();
    await _refreshNotification();
  }

  Future<void> setRemindBefore(bool value) async {
    await settings.setRemindBefore(value);
    notifyListeners();
    await _refreshNotification();
  }

  Future<void> setRemindStart(bool value) async {
    await settings.setRemindStart(value);
    notifyListeners();
    await _refreshNotification();
  }

  Future<void> setRemindEnd(bool value) async {
    await settings.setRemindEnd(value);
    notifyListeners();
    await _refreshNotification();
  }

  Future<void> setRemindLeadSeconds(int value) async {
    await settings.setRemindLeadSeconds(value);
    notifyListeners();
    await _refreshNotification();
  }

  Future<void> _refreshNotification() async {
    final svc = schedule;
    if (hasSchedule && svc != null) {
      await LiveNotification.start(
        svc.scheduleFor(DateTime.now()),
        enhancedCountdown: settings.enhancedCountdown,
        remindBefore: settings.remindBefore,
        remindStart: settings.remindStart,
        remindEnd: settings.remindEnd,
        remindLeadSeconds: settings.remindLeadSeconds,
      );
    } else {
      await LiveNotification.stop();
    }
  }

  /// 导入新课表时按 courseId（回退 title）从上一张选中课表带过已填的教室，
  /// 避免换学期/重导后要重填走班教室。
  static Calendar _mergeRooms(Calendar incoming, Calendar? old) {
    if (old == null || old.courses.isEmpty) return incoming;

    final roomByTitle = <String, String>{};
    for (final c in old.courses.values) {
      if (c.defaultLocation.isNotEmpty) roomByTitle[c.title] = c.defaultLocation;
    }
    final courses = <String, CourseEvent>{};
    incoming.courses.forEach((id, c) {
      var room = c.defaultLocation;
      if (room.isEmpty) {
        final byId = old.courses[id];
        room = (byId != null && byId.defaultLocation.isNotEmpty)
            ? byId.defaultLocation
            : (roomByTitle[c.title] ?? '');
      }
      courses[id] = c.copyWith(defaultLocation: room);
    });
    return incoming.copyWith(courses: courses);
  }
}
