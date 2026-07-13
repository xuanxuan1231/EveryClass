import 'package:everyclass/app_state.dart';
import 'package:everyclass/data/profile_repository.dart';
import 'package:everyclass/models/profile.dart';
import 'package:everyclass/services/settings_service.dart';
import 'package:everyclass/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryProfileRepository implements ProfileRepository {
  Profile? profile;

  _MemoryProfileRepository(this.profile);

  @override
  Future<void> clear() async => profile = null;

  @override
  Future<Profile?> load() async => profile;

  @override
  Future<void> save(Profile value) async => profile = value;
}

Future<AppState> _createAppState() async {
  SharedPreferences.setMockInitialValues({});
  final settings = await SettingsService.create();
  return AppState(
    _MemoryProfileRepository(Profile.empty()),
    settings,
    Profile.empty(),
  );
}

Widget _wrap(AppState app) => ChangeNotifierProvider.value(
  value: app,
  child: const MaterialApp(home: SettingsScreen()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('everyclass/live_notification');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('Debug 设置页可启动五分钟实时活动演示', (tester) async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    await tester.pumpWidget(_wrap(await _createAppState()));

    expect(find.text('开发：预览实时活动'), findsOneWidget);

    await tester.tap(find.text('开发：预览实时活动'));
    await tester.pump();

    expect(calls.single.method, 'update');
    expect(find.text('已启动演示实时活动'), findsOneWidget);
  });

  testWidgets('演示不可用时显示原因', (tester) async {
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    await tester.pumpWidget(_wrap(await _createAppState()));

    await tester.tap(find.text('开发：预览实时活动'));
    await tester.pump();

    expect(find.text('当前设备不支持或未启用实时活动'), findsOneWidget);
  });
}
