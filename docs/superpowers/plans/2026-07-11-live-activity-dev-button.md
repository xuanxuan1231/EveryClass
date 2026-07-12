# Live Activity 开发预览按钮 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Debug 设置页中提供一个可启动五分钟 Live Activity 演示的开发入口。

**Architecture:** `LiveNotification.runDemo()` 继续生成平台无关的五分钟展示状态并调用既有 MethodChannel。`SettingsScreen` 只在 `kDebugMode` 为真时渲染一个 `ListTile`，等待调用结束后通过既有 SnackBar 反馈结果；它不读取或修改 `AppState` 的通知设置和档案数据。

**Tech Stack:** Flutter/Dart、Material、Provider、Flutter widget tests、MethodChannel mock。

## Global Constraints

- 入口必须由 Flutter `kDebugMode` 守卫，因此 Profile 和 Release 构建不包含该 UI。
- 标题为“开发：预览实时活动”，副标题说明启动五分钟演示。
- 点击只能调用 `LiveNotification.runDemo()`，不写入 SharedPreferences、不修改课表或实时通知开关。
- `true` 显示“已启动演示实时活动”；`false` 显示“当前设备不支持或未启用实时活动”。
- 不新增 package 或原生代码；重复点击依赖原生层既有单 Activity 复用语义。

---

### Task 1: 设置页开发预览入口

**Files:**
- Create: `test/settings_screen_test.dart`
- Modify: `lib/ui/settings_screen.dart:1-93`

**Interfaces:**
- Consumes: `LiveNotification.runDemo() -> Future<bool>` from `lib/platform/live_notification.dart`.
- Produces: Debug-only `ListTile` in `SettingsScreen` and `_runLiveActivityDemo(BuildContext) -> Future<void>` feedback handler.

- [ ] **Step 1: Write the failing widget tests**

Create `test/settings_screen_test.dart` with a test app that constructs `AppState` from an in-memory `ProfileRepository`, initializes `SharedPreferences` with `setMockInitialValues({})`, and wraps `SettingsScreen` in `ChangeNotifierProvider.value` and `MaterialApp`. Register a mock for `MethodChannel('everyclass/live_notification')` before each test and clear it after each test.

```dart
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
```

```dart
testWidgets('演示不可用时显示原因', (tester) async {
  messenger.setMockMethodCallHandler(channel, (_) async => false);
  await tester.pumpWidget(_wrap(await _createAppState()));
  await tester.tap(find.text('开发：预览实时活动'));
  await tester.pump();
  expect(find.text('当前设备不支持或未启用实时活动'), findsOneWidget);
});
```

- [ ] **Step 2: Run the test file to verify the missing UI fails**

Run: `flutter test test/settings_screen_test.dart`

Expected: FAIL because the finder for “开发：预览实时活动” finds no widget.

- [ ] **Step 3: Add the Debug-only tile and feedback handler**

In `lib/ui/settings_screen.dart`, import `package:flutter/foundation.dart` and `../platform/live_notification.dart`. Directly after the existing real-time-notification controls, conditionally add this collection:

```dart
if (kDebugMode) ...[
  const Divider(height: 1),
  ListTile(
    leading: const Icon(Icons.bug_report_outlined),
    title: const Text('开发：预览实时活动'),
    subtitle: const Text('启动五分钟演示课程，用于检查锁屏和灵动岛显示'),
    onTap: () => _runLiveActivityDemo(context),
  ),
],
```

Add this handler beside `_snack`:

```dart
Future<void> _runLiveActivityDemo(BuildContext context) async {
  final started = await LiveNotification.runDemo();
  if (!context.mounted) return;
  _snack(
    context,
    started ? '已启动演示实时活动' : '当前设备不支持或未启用实时活动',
  );
}
```

- [ ] **Step 4: Run focused tests and static analysis**

Run: `flutter test test/settings_screen_test.dart && flutter analyze`

Expected: both commands exit with status 0; the success test observes exactly one `update` method call, and the unavailable test sees its error message.

- [ ] **Step 5: Run the complete test suite**

Run: `flutter test`

Expected: all existing and new tests pass.

- [ ] **Step 6: Commit the implementation**

Run: `git add lib/ui/settings_screen.dart test/settings_screen_test.dart docs/superpowers/plans/2026-07-11-live-activity-dev-button.md && git commit -m "feat(settings): add debug live activity preview"`

## Manual iOS Verification

- [ ] Run `flutter run` on an iOS 16.2-or-newer simulator or device with Live Activities enabled.
- [ ] Open “设置”, tap “开发：预览实时活动”, then confirm the lock screen shows “演示课程” with a five-minute countdown.
- [ ] On a Dynamic Island-capable target, inspect compact, minimal, and expanded presentations.
