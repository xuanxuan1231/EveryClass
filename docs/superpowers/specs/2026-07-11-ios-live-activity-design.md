# iOS Live Activity 原生通知设计

## 目标

在 `iOS` 分支中完成 EveryClass 的原生实时通知层，使 Flutter 以后只需通过统一的 MethodChannel 传入课程展示数据，即可在 Android 常驻通知与 iOS 锁屏实时活动、灵动岛中显示。当前阶段不依赖尚未稳定的课表模型，也不新增正式 UI。

## 范围

本次实现会把现有 `ActivityKit`、`WidgetKit` 和 SwiftUI 文件真正加入 Xcode 工程，创建可构建的 `ClassWidget` Widget Extension target，并确保 Runner 内的 Flutter 插件能够启动、更新和结束 Live Activity。Android 与 iOS 继续共用 `everyclass/live_notification` 通道。

为便于在课表模型未完成时验证完整链路，Flutter 侧提供一个由 `--dart-define` 显式开启的演示入口。演示模式使用固定课程文案和相对当前时间计算的倒计时；普通构建不会自动显示测试通知。

本次不实现课表解析、正式设置界面、APNs 远程更新、App Group 数据共享或后台长期调度。iOS 16.2 以下设备会返回不支持，不尝试降级成普通本地通知。

## 方案与接口

保留现有 `start` 和 `stop`，补齐直接更新展示状态的能力与可用性查询。通道协议与课表模型分离，参数仅使用 Flutter 标准编解码器支持的基本类型。

### MethodChannel

通道名保持为 `everyclass/live_notification`。

- `isSupported`：无参数，返回当前平台和系统是否支持实时通知。
- `start`：接收现有 `lessons` 数组，兼容当前 Android 调度逻辑和已有 Flutter 调用。
- `update`：接收单条平台无关展示状态，包括 `subject`、`room`、`teacher`、`phase`、`statusLabel`、`countdownStartEpochMs` 和 `countdownEndEpochMs`。
- `stop`：立即结束并移除当前实时通知。

所有方法都必须恰好回调一次 Flutter result。非法参数返回明确的 `FlutterError`；系统不支持或用户关闭 Live Activities 时返回可识别结果，不让 Flutter UI 崩溃。Dart 包装层保留安全调用，但向调用方暴露布尔结果，便于以后在 Flutter 中决定是否提示用户。

## iOS 工程结构

`Runner` target 包含 `LiveActivityPlugin.swift`、`LiveActivityManager.swift` 和共享的 `ClassActivityAttributes.swift`。`ClassWidget` target 包含 Widget bundle、灵动岛/锁屏视图以及同一份共享 attributes 文件。Extension 会作为 Runner 的嵌入式 App Extension 构建产物，并使用 Runner Bundle ID 的子标识。

`ClassWidget` 的最低部署版本为 iOS 16.2；Runner 保持现有部署范围，并用系统版本检查保护 ActivityKit 调用，因此旧系统仍可启动 App，只是不提供 Live Activity。Runner 的 `Info.plist` 保持 `NSSupportsLiveActivities`。不添加 App Group，因为当前数据从正在运行的 Flutter App 通过 MethodChannel 进入原生层。

## 生命周期与数据流

Flutter 调用 `start` 时，原生层将课程时间换算为当天绝对时间，选取当前或下一节课，然后请求或更新唯一的 Live Activity。Flutter 调用 `update` 时，原生层直接用传入状态请求或更新同一个 Activity，不依赖课程模型。倒计时由 WidgetKit 的时间区间文本原生刷新。

若进程内已有 EveryClass Live Activity，Manager 会复用它，避免重复创建。调用 `stop` 会取消定时器并结束所有由当前 attributes 类型创建的活动。App 在前台时可按课程边界刷新；本阶段不承诺进程被系统挂起后的自动切课。

演示模式在 Flutter 初始化完成后调用 `update`，生成一条持续数分钟的固定测试课程。它只在编译参数 `EVERYCLASS_NOTIFICATION_DEMO=true` 时运行。

## 错误处理

原生层校验必填字符串与时间区间，结束时间必须晚于开始时间。ActivityKit 请求或更新失败时记录带 `[EveryClass]` 前缀的系统日志，并将可处理错误返回 Flutter。若 Live Activities 被系统禁用，不创建活动并返回禁用状态。重复停止视为成功。

## 验证

静态验证包括 Flutter analyze/test、Xcode 工程结构检查和 Swift 编译。可用 macOS/Xcode 环境时，运行 iOS 模拟器构建；灵动岛最终验收需要支持灵动岛的 iPhone 或相应模拟器、iOS 16.2 以上系统，并启用实时活动。

手工验收使用演示参数启动 App，确认锁屏实时活动出现，支持设备上灵动岛紧凑、最小和展开状态均可显示，倒计时递减；随后调用停止路径，确认活动立即消失。普通启动不得自动创建演示活动。

## 文档交付

新增 `ios/README.md`，说明架构、通道字段、构建要求、签名配置、演示启动命令、真机验收方法、系统限制和常见故障。根 `README.md` 会链接到该文档，现有 `ios/LIVE_ACTIVITY_SETUP.md` 的有效内容将合并进去，避免继续维护“需要手动挂接 Xcode 文件”的过时步骤。

## 完成标准

`WindySlime/EveryClass` 的 `iOS` 分支包含可构建的 ClassWidget Extension；无需手动往 Xcode 添加源码文件；Flutter 能以统一通道启动、更新和停止通知；无课表时可通过显式演示参数验证；默认构建无测试通知；README 足以让另一位开发者完成签名、运行和验收。
