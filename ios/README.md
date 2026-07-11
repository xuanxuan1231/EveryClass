# EveryClass iOS Live Activity

EveryClass 的 iOS 实时通知由 Runner 中的 Flutter 插件和内嵌的 `ClassWidget` Widget Extension 组成。工程已经完成 target、源码 membership、依赖和 Embed App Extensions 配置；克隆后不需要再手动向 Xcode 添加 Swift 文件。

## 架构

`lib/platform/live_notification.dart` 通过 `everyclass/live_notification` 通道发送平台无关数据。Runner 中的 `LiveActivityPlugin.swift` 负责参数校验与 Flutter 结果回调，`LiveActivityManager.swift` 负责创建、复用、更新和结束 ActivityKit 活动。`ClassActivityAttributes.swift` 同时编译进 Runner 与 ClassWidget，保证两侧状态结构一致。`ClassWidgetLiveActivity.swift` 渲染锁屏、横幅和灵动岛的展开、紧凑与最小状态。

`start` 会从当天课程中选择当前或下一节并在 App 前台运行时按课程边界刷新。`update` 直接展示调用方传入的状态，不依赖课表模型。WidgetKit 使用时间区间文本刷新倒计时，不需要 Flutter 每秒更新。

## MethodChannel 协议

通道名固定为 `everyclass/live_notification`。所有操作成功时返回 `true`，平台不支持、Live Activities 被用户关闭或原生请求失败时返回 `false`。Dart 包装层会把缺失插件和 `PlatformException` 安全转换为 `false`；原生参数错误使用 `invalid_arguments` 返回明确的 `FlutterError`。

| 方法 | 参数 |
| --- | --- |
| `isSupported` | 无参数 |
| `start` | `{ enhancedCountdown, lessons }`；每节课包含 `subject`、`room`、`teacher`、`period`、`startMs`、`endMs`，其中时间是距当天零点的毫秒数 |
| `update` | `subject`、`room`、`teacher`、`phase`、`statusLabel`、`countdownStartEpochMs`、`countdownEndEpochMs` |
| `stop` | 无参数；重复调用也返回成功 |

`subject`、`phase` 和 `statusLabel` 必须是非空字符串；`room`、`teacher` 必须是字符串但允许为空；倒计时结束时间必须晚于开始时间。

## 构建与签名

需要 macOS、Xcode、Flutter stable 和 iOS 16.2 以上的模拟器或设备。Runner 仍支持原有 iOS 13.0 最低版本；低于 iOS 16.2 的系统可以启动 App，但 `isSupported` 返回 `false`，不会降级为普通本地通知。

使用 Xcode 时打开 `ios/Runner.xcworkspace`。在 Runner 和 ClassWidget 两个 target 的 Signing & Capabilities 中选择同一个开发团队，并确保 ClassWidget 的 Bundle ID 是 Runner Bundle ID 的子标识。仓库默认值分别是 `com.example.everyclass` 和 `com.example.everyclass.ClassWidget`。当前实现不需要 App Group。

常规检查与构建：

```bash
flutter pub get
flutter analyze
flutter test
flutter build ios --simulator --debug
```

## 演示与验收

没有课表数据时，可以显式启用五分钟的固定演示课程：

```bash
flutter run --dart-define=EVERYCLASS_NOTIFICATION_DEMO=true
```

普通 `flutter run` 和发布构建不会自动创建演示活动。演示参数只在 Flutter 初始化完成后调用一次 `update`。

在 iOS 16.2 以上、已启用 Live Activities 的模拟器或真机上验收：启动演示后锁屏活动应出现且倒计时递减；支持灵动岛的设备还应检查展开、紧凑和最小状态；课程名、教室、教师、阶段和倒计时标签应可读。随后从调用方执行 `LiveNotification.stop()`，活动应立即消失。最终显示效果应在支持灵动岛的 iPhone 或对应模拟器上确认。

## 限制与排障

本阶段不包含 APNs 远程更新、App Group、后台长期调度或课表解析。App 在前台时可以按课程边界切换；进程挂起后不承诺自动切到下一节。

若活动没有出现，先确认系统版本至少为 iOS 16.2、系统设置中允许 Live Activities、`LiveNotification.isSupported()` 返回 `true`，并检查控制台中带 `[EveryClass]` 前缀的日志。若 ClassWidget 无法签名，确认两个 target 使用同一团队且 extension Bundle ID 以 App Bundle ID 为前缀。若 Xcode 找不到生成的 Flutter package，先在仓库根目录运行 `flutter pub get`，再重新打开 workspace。
