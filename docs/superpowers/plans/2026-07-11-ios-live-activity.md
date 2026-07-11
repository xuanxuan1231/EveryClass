# iOS Live Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a buildable `ClassWidget` extension and a unified Flutter notification channel that can start, update, query, and stop iOS Live Activities without requiring a populated timetable.

**Architecture:** `LiveNotification` is the platform-neutral Dart interface and owns StandardMessageCodec payloads plus safe boolean results. `LiveActivityPlugin` validates Flutter calls and translates them into `LessonInput` or `ClassActivityAttributes.ContentState`; `LiveActivityManager` exclusively owns ActivityKit lifecycle, reuse, timers, and ending all EveryClass activities. The same activity attributes source is compiled into Runner and ClassWidget, while the extension renders lock-screen and Dynamic Island views.

**Tech Stack:** Flutter/Dart MethodChannel, Swift 5, ActivityKit, WidgetKit, SwiftUI, Kotlin/Android foreground service, Xcode project format.

## Global Constraints

- Keep the MethodChannel name exactly `everyclass/live_notification`.
- Keep Runner's existing iOS 13.0 deployment range; guard all ActivityKit calls with iOS 16.2 availability.
- Set ClassWidget's minimum deployment version to iOS 16.2.
- Do not add App Groups, APNs updates, background scheduling, a formal settings UI, or timetable parsing.
- Only run the demo when `EVERYCLASS_NOTIFICATION_DEMO=true` is supplied through `--dart-define`.
- All native methods call the Flutter result exactly once; invalid arguments produce explicit platform errors.
- Default builds never create demo notifications.

---

### Task 1: Flutter notification interface and demo

**Files:**
- Modify: `lib/platform/live_notification.dart`
- Modify: `lib/main.dart`
- Create: `test/live_notification_test.dart`

**Interfaces:**
- Consumes: Flutter `MethodChannel` and `DaySchedule`.
- Produces: `LiveNotification.isSupported() -> Future<bool>`, `start(...) -> Future<bool>`, `update(LiveNotificationState) -> Future<bool>`, `stop() -> Future<bool>`, and `runNotificationDemo() -> Future<bool>`.

- [ ] **Step 1: Write the failing public-interface test**

Use `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler` to assert that `isSupported`, `start`, `update`, and `stop` return native booleans. Assert that `update` sends subject, room, teacher, phase, statusLabel, and the two epoch-millisecond fields.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `flutter test test/live_notification_test.dart`

Expected: compilation fails because `LiveNotificationState`, `isSupported`, and `update` do not exist and `start`/`stop` return `Future<void>`.

- [ ] **Step 3: Implement the Dart interface**

Add an immutable display-state value with required non-empty display strings and `DateTime countdownStart/countdownEnd`. Encode dates with `millisecondsSinceEpoch`. Make `_safe` return `false` for missing plugins, platform errors, null, or non-boolean responses, while preserving UI safety.

- [ ] **Step 4: Add the demo entry point**

Define `const notificationDemoEnabled = bool.fromEnvironment('EVERYCLASS_NOTIFICATION_DEMO')`. After Flutter binding and app-state initialization, invoke a helper only when the constant is true; the helper sends fixed course copy with a countdown based on the current clock. Keep this helper callable from tests with an injected `DateTime`.

- [ ] **Step 5: Verify GREEN**

Run: `flutter test test/live_notification_test.dart`

Expected: all notification interface and demo tests pass.

### Task 2: Native channel compatibility

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/everyclass/MainActivity.kt`
- Modify: `ios/Runner/LiveActivityPlugin.swift`
- Modify: `ios/Runner/LiveActivityManager.swift`
- Modify: `ios/RunnerTests/RunnerTests.swift`

**Interfaces:**
- Consumes: StandardMessageCodec maps from Task 1.
- Produces: `isSupported`, `start`, `update`, and `stop` native handlers returning one boolean result; invalid iOS payloads return `FlutterError(code: "invalid_arguments", ...)`.

- [ ] **Step 1: Add Swift parsing tests**

Exercise public/internal parser functions with a valid display-state map, a missing required string, and an end time not later than start. Assert valid absolute dates and explicit thrown validation errors.

- [ ] **Step 2: Run RunnerTests and verify RED**

Run: `xcodebuild test -project ios/Runner.xcodeproj -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO`

Expected: tests fail because direct-state parsing and validation do not exist.

- [ ] **Step 3: Implement iOS validation and result handling**

Parse lessons strictly enough to reject malformed `lessons` containers and invalid lesson times. Parse direct state using the seven documented keys, trim required display strings, enforce `countdownEnd > countdownStart`, and call async manager methods from one Task that invokes the result once. Return `false` on iOS below 16.2 or when system authorization disables activities.

- [ ] **Step 4: Deepen LiveActivityManager**

Have `apply(lessons:)`, `update(state:)`, and `stop()` return success asynchronously. Reuse an existing `Activity<ClassActivityAttributes>` from `Activity.activities` before requesting another. End every activity of that attributes type on stop, cancel timers, log request/update failures with `[EveryClass]`, and retain foreground schedule-boundary refresh for `start`.

- [ ] **Step 5: Add Android unified-method support**

Return `true` from `isSupported`. Convert `update`'s absolute epoch interval into the existing service's lesson JSON and start the same foreground service; validate the required fields and return a `bad_args` error on malformed input. Preserve existing `start` and `stop` behavior.

- [ ] **Step 6: Re-run focused native tests**

Run the RunnerTests command from Step 2.

Expected: parser and lifecycle-adapter tests pass.

### Task 3: Xcode Widget Extension integration

**Files:**
- Modify: `ios/Runner.xcodeproj/project.pbxproj`
- Modify: `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`
- Modify: `ios/ClassWidget/Info.plist`
- Modify: `ios/ClassWidget/ClassWidgetLiveActivity.swift`

**Interfaces:**
- Consumes: `ClassActivityAttributes` compiled from `ios/Runner/ClassActivityAttributes.swift`.
- Produces: embedded `ClassWidget.appex` with bundle identifier `$(PRODUCT_BUNDLE_IDENTIFIER).ClassWidget`, iOS 16.2 floor, WidgetKit extension point, and Live Activity lock-screen/Dynamic Island UI.

- [ ] **Step 1: Add all PBX references and memberships**

Add Runner source membership for `LiveActivityPlugin.swift`, `LiveActivityManager.swift`, and `ClassActivityAttributes.swift`. Add a ClassWidget group and target compiling `ClassWidgetBundle.swift`, `ClassWidgetLiveActivity.swift`, and the shared attributes file.

- [ ] **Step 2: Add product embedding and dependency**

Create `ClassWidget.appex`, its sources/frameworks/resources phases, Runner target dependency, and an Embed App Extensions copy phase using `dstSubfolderSpec = 13` with code signing on copy.

- [ ] **Step 3: Add target build settings**

For Debug/Profile/Release set `INFOPLIST_FILE = ClassWidget/Info.plist`, `IPHONEOS_DEPLOYMENT_TARGET = 16.2`, `PRODUCT_BUNDLE_IDENTIFIER = com.example.everyclass.ClassWidget`, `SKIP_INSTALL = YES`, `APPLICATION_EXTENSION_API_ONLY = YES`, Swift 5, and matching version values.

- [ ] **Step 4: Validate project structure**

Run: `plutil -lint ios/Runner.xcodeproj/project.pbxproj ios/Runner/Info.plist ios/ClassWidget/Info.plist`

Run: `xcodebuild -project ios/Runner.xcodeproj -list`

Expected: all files parse and `ClassWidget` appears in targets.

- [ ] **Step 5: Compile the iOS simulator app**

Run: `xcodebuild -project ios/Runner.xcodeproj -scheme Runner -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`

Expected: Runner and ClassWidget compile, and the built Runner app contains `PlugIns/ClassWidget.appex`.

### Task 4: Documentation and final verification

**Files:**
- Create: `ios/README.md`
- Delete: `ios/LIVE_ACTIVITY_SETUP.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: finalized channel and Xcode configuration.
- Produces: one maintained iOS setup/run/troubleshooting guide linked from the root README.

- [ ] **Step 1: Write the consolidated iOS guide**

Document architecture, every MethodChannel field and boolean/error result, Xcode/macOS requirements, signing for Runner and ClassWidget, the exact `flutter run --dart-define=EVERYCLASS_NOTIFICATION_DEMO=true` command, default-build behavior, device acceptance checks, ActivityKit limitations, and common troubleshooting.

- [ ] **Step 2: Remove obsolete manual setup instructions**

Delete `ios/LIVE_ACTIVITY_SETUP.md` after migrating still-valid signing and acceptance content. Update the root README architecture and development links to `ios/README.md`, stating that the extension is already wired into Xcode.

- [ ] **Step 3: Run Dart validation**

Run: `flutter analyze`

Run: `flutter test`

Expected: analyzer reports no issues and all tests pass.

- [ ] **Step 4: Run final Xcode validation**

Repeat the plist/project checks, RunnerTests, and generic simulator build from Tasks 2 and 3.

- [ ] **Step 5: Review the complete diff**

Compare every section of `docs/superpowers/specs/2026-07-11-ios-live-activity-design.md` against the diff. Confirm no demo call exists outside the compile-time flag, all channel calls return exactly once, and no unrelated files changed.

- [ ] **Step 6: Commit**

```bash
git add README.md docs/superpowers/plans/2026-07-11-ios-live-activity.md lib test android ios
git commit -m "feat(ios): integrate class live activities"
```
