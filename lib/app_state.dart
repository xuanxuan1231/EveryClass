import 'package:flutter/foundation.dart';

import 'data/classisland_importer.dart';
import 'data/local_profile_repository.dart';
import 'data/profile_repository.dart';
import 'models/profile.dart';
import 'models/subject.dart';
import 'platform/live_notification.dart';
import 'services/schedule_service.dart';
import 'services/settings_service.dart';

/// 应用级状态：持有档案与设置，暴露导入/教室/通知等操作，变更后驱动 UI 与通知刷新。
class AppState extends ChangeNotifier {
  final ProfileRepository _repo;
  final SettingsService settings;
  Profile _profile;

  AppState(this._repo, this.settings, this._profile);

  static Future<AppState> create() async {
    final repo = LocalProfileRepository();
    final settings = await SettingsService.create();
    final profile = await repo.load() ?? Profile.empty();
    final state = AppState(repo, settings, profile);
    // 启动时若已开启通知且有课表，刷新一次。
    await state._refreshNotification();
    return state;
  }

  Profile get profile => _profile;

  ScheduleService get schedule =>
      ScheduleService(_profile, termStart: settings.termStart);

  /// 是否已导入可用课表（有时间表且有课表定义）。
  bool get hasSchedule =>
      _profile.timeLayouts.isNotEmpty && _profile.classPlans.isNotEmpty;

  /// 当前是学期第几周（未设学期起始日则为 null）。
  int? get weekNumber {
    final ts = settings.termStart;
    if (ts == null) return null;
    final monday = ts.subtract(Duration(days: ts.weekday - 1));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today
        .difference(DateTime(monday.year, monday.month, monday.day))
        .inDays;
    if (diff < 0) return null;
    return diff ~/ 7 + 1;
  }

  /// 导入 ClassIsland 档案文本；抛出的 [ImportException] 由调用方展示。
  Future<void> importFromText(String jsonText) async {
    final imported = ClassIslandImporter.parse(jsonText);
    _profile = _mergeRooms(imported, _profile);
    await _repo.save(_profile);
    notifyListeners();
    await _refreshNotification();
  }

  /// 设置某科目的默认教室（走班场景补齐 ClassIsland 缺失的教室）。
  Future<void> setSubjectRoom(String subjectId, String room) async {
    final subject = _profile.subjects[subjectId];
    if (subject == null) return;
    final subjects = Map<String, Subject>.from(_profile.subjects);
    subjects[subjectId] = subject.copyWith(defaultRoom: room.trim());
    _profile = _profile.copyWith(subjects: subjects);
    await _repo.save(_profile);
    notifyListeners();
    await _refreshNotification();
  }

  Future<void> setTermStart(DateTime? day) async {
    await settings.setTermStart(day);
    notifyListeners();
    await _refreshNotification();
  }

  Future<void> setNotificationEnabled(bool value) async {
    await settings.setNotificationEnabled(value);
    notifyListeners();
    await _refreshNotification();
  }

  Future<void> setEnhancedCountdown(bool value) async {
    await settings.setEnhancedCountdown(value);
    notifyListeners();
    await _refreshNotification();
  }

  Future<void> _refreshNotification() async {
    if (settings.notificationEnabled && hasSchedule) {
      await LiveNotification.start(
        schedule.scheduleFor(DateTime.now()),
        enhancedCountdown: settings.enhancedCountdown,
      );
    } else {
      await LiveNotification.stop();
    }
  }

  /// 再导入时按 subjectId（回退 name）保留已填的教室，避免每次导入都要重填。
  static Profile _mergeRooms(Profile incoming, Profile old) {
    if (old.subjects.isEmpty) return incoming;
    final roomByName = <String, String>{};
    for (final s in old.subjects.values) {
      if (s.defaultRoom.isNotEmpty) roomByName[s.name] = s.defaultRoom;
    }
    final subjects = <String, Subject>{};
    incoming.subjects.forEach((id, s) {
      var room = s.defaultRoom;
      if (room.isEmpty) {
        final byId = old.subjects[id];
        room = (byId != null && byId.defaultRoom.isNotEmpty)
            ? byId.defaultRoom
            : (roomByName[s.name] ?? '');
      }
      subjects[id] = s.copyWith(defaultRoom: room);
    });
    return incoming.copyWith(subjects: subjects);
  }
}
