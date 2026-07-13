import 'package:flutter/foundation.dart';

import 'data/classisland_importer.dart';
import 'data/database_repository.dart';
import 'data/local_database_repository.dart';
import 'models/calendar.dart';
import 'models/course_event.dart';
import 'models/database.dart';
import 'platform/live_notification.dart';
import 'services/schedule_service.dart';
import 'services/settings_service.dart';

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

  /// 导入 ClassIsland 档案文本（导入即转换）；抛出的 [ImportException] 由调用方展示。
  Future<void> importFromText(String jsonText) async {
    final imported = ClassIslandImporter.parse(
      jsonText,
      firstWeekStart: firstWeekStart,
    );
    _db = _mergeRooms(imported, _db);
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

  /// 设置学期第一周所在日期（写入选中 Calendar 的 firstWeekStart）。
  Future<void> setFirstWeekStart(DateTime? day) async {
    final cal = calendar;
    if (cal == null) return;
    final normalized =
        day == null ? null : DateTime(day.year, day.month, day.day);
    _db = _db.withCalendar(cal.copyWith(
      firstWeekStart: normalized,
      clearFirstWeekStart: normalized == null,
    ));
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

  /// 再导入时按 courseId（回退 title）保留已填的教室，避免每次导入都要重填。
  static Database _mergeRooms(Database incoming, Database old) {
    final oldCal = old.selected;
    final newCal = incoming.selected;
    if (oldCal == null || newCal == null) return incoming;
    if (oldCal.courses.isEmpty) return incoming;

    final roomByTitle = <String, String>{};
    for (final c in oldCal.courses.values) {
      if (c.defaultLocation.isNotEmpty) roomByTitle[c.title] = c.defaultLocation;
    }
    final courses = <String, CourseEvent>{};
    newCal.courses.forEach((id, c) {
      var room = c.defaultLocation;
      if (room.isEmpty) {
        final byId = oldCal.courses[id];
        room = (byId != null && byId.defaultLocation.isNotEmpty)
            ? byId.defaultLocation
            : (roomByTitle[c.title] ?? '');
      }
      courses[id] = c.copyWith(defaultLocation: room);
    });
    return incoming.withCalendar(newCal.copyWith(courses: courses));
  }
}
