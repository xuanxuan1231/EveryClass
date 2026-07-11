import Flutter
import Foundation

/// 把 Flutter 的 `everyclass/live_notification` 通道桥接到 iOS Live Activity。
///
/// 复用与 Android 相同的通道与 `start`/`stop` 协议，Dart 侧无需区分平台。
public class LiveActivityPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "everyclass/live_notification",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(LiveActivityPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            if #available(iOS 16.2, *) {
                LiveActivityManager.shared.apply(lessons: Self.parseLessons(call.arguments))
            }
            result(nil)
        case "stop":
            if #available(iOS 16.2, *) {
                LiveActivityManager.shared.stop()
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// 解析 `{ lessons: [{subject, room, teacher, period, startMs, endMs}, ...] }`。
    /// startMs/endMs 为"距零点的毫秒"，加今天零点得到绝对时间。
    private static func parseLessons(_ arguments: Any?) -> [LessonInput] {
        guard let dict = arguments as? [String: Any],
              let raw = dict["lessons"] as? [[String: Any]] else {
            return []
        }
        let base = Calendar.current.startOfDay(for: Date())
        return raw.map { m in
            let startMs = (m["startMs"] as? NSNumber)?.doubleValue ?? 0
            let endMs = (m["endMs"] as? NSNumber)?.doubleValue ?? 0
            return LessonInput(
                subject: m["subject"] as? String ?? "",
                room: m["room"] as? String ?? "",
                teacher: m["teacher"] as? String ?? "",
                start: base.addingTimeInterval(startMs / 1000.0),
                end: base.addingTimeInterval(endMs / 1000.0)
            )
        }
    }
}
