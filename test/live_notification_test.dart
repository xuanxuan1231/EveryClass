import 'package:everyclass/models/resolved_lesson.dart';
import 'package:everyclass/platform/live_notification.dart';
import 'package:everyclass/services/schedule_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _mathLesson = ResolvedLesson(
  subjectId: 'math',
  subjectName: '数学',
  teacher: '李老师',
  room: 'A101',
  period: 1,
  start: Duration(hours: 8),
  end: Duration(hours: 8, minutes: 45),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('everyclass/live_notification');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('统一通道返回原生可用性与操作结果', () async {
    final day = DaySchedule(
      day: DateTime(2026, 7, 11),
      lessons: const [_mathLesson],
    );

    expect(await LiveNotification.isSupported(), isTrue);
    expect(await LiveNotification.start(day), isTrue);
    expect(await LiveNotification.stop(), isTrue);

    expect(calls.map((call) => call.method), ['isSupported', 'start', 'stop']);
  });

  test('update 使用平台无关展示状态和 epoch 毫秒', () async {
    final start = DateTime.fromMillisecondsSinceEpoch(1_752_200_000_000);
    final end = start.add(const Duration(minutes: 45));

    final success = await LiveNotification.update(
      LiveNotificationState(
        subject: '数学',
        room: 'A101',
        teacher: '李老师',
        phase: '上课中',
        statusLabel: '距下课',
        countdownStart: start,
        countdownEnd: end,
      ),
    );

    expect(success, isTrue);
    expect(calls.single.method, 'update');
    expect(calls.single.arguments, {
      'subject': '数学',
      'room': 'A101',
      'teacher': '李老师',
      'phase': '上课中',
      'statusLabel': '距下课',
      'countdownStartEpochMs': start.millisecondsSinceEpoch,
      'countdownEndEpochMs': end.millisecondsSinceEpoch,
    });
  });

  test('start 下发课程提醒设置', () async {
    final day = DaySchedule(
      day: DateTime(2026, 7, 11),
      lessons: const [_mathLesson],
    );

    expect(
      await LiveNotification.start(
        day,
        enhancedCountdown: true,
        remindBefore: true,
        remindStart: true,
        remindEnd: true,
        remindLeadSeconds: 180,
      ),
      isTrue,
    );

    expect(calls.single.method, 'start');
    final arguments = calls.single.arguments! as Map<Object?, Object?>;
    expect(arguments['enhancedCountdown'], isTrue);
    expect(arguments['remindBefore'], isTrue);
    expect(arguments['remindStart'], isTrue);
    expect(arguments['remindEnd'], isTrue);
    expect(arguments['remindLeadSeconds'], 180);
  });

  test('演示状态以当前时间生成且只走 update', () async {
    final now = DateTime(2026, 7, 11, 9, 30);

    expect(await LiveNotification.runDemo(now: now), isTrue);

    expect(calls.single.method, 'update');
    final arguments = calls.single.arguments! as Map<Object?, Object?>;
    expect(arguments['subject'], '演示课程');
    expect(arguments['phase'], '上课中');
    expect(arguments['countdownStartEpochMs'], now.millisecondsSinceEpoch);
    expect(
      arguments['countdownEndEpochMs'],
      now.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
    );
  });

  test('平台缺失、异常或非布尔结果安全返回 false', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(await LiveNotification.isSupported(), isFalse);

    messenger.setMockMethodCallHandler(channel, (call) async => 'yes');
    expect(await LiveNotification.isSupported(), isFalse);

    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'disabled'),
    );
    expect(await LiveNotification.stop(), isFalse);

    messenger.setMockMethodCallHandler(channel, null);
    expect(await LiveNotification.isSupported(), isFalse);
  });
}
