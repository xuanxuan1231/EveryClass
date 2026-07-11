import Flutter
import Foundation

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
        case "isSupported":
            guard #available(iOS 16.2, *) else {
                result(false)
                return
            }
            Task { @MainActor in
                result(LiveActivityManager.shared.isSupported)
            }
        case "start":
            guard #available(iOS 16.2, *) else {
                result(false)
                return
            }
            do {
                let lessons = try Self.parseLessons(call.arguments)
                Task { @MainActor in
                    result(await LiveActivityManager.shared.apply(lessons: lessons))
                }
            } catch {
                result(Self.flutterError(error))
            }
        case "update":
            guard #available(iOS 16.2, *) else {
                result(false)
                return
            }
            do {
                let state = try Self.parseState(call.arguments)
                Task { @MainActor in
                    result(await LiveActivityManager.shared.update(state: state))
                }
            } catch {
                result(Self.flutterError(error))
            }
        case "stop":
            guard #available(iOS 16.2, *) else {
                result(true)
                return
            }
            Task { @MainActor in
                result(await LiveActivityManager.shared.stop())
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    static func parseLessons(_ arguments: Any?, now: Date = Date()) throws -> [LessonInput] {
        guard let dict = arguments as? [String: Any],
              let raw = dict["lessons"] as? [[String: Any]] else {
            throw LiveActivityInputError.invalid("lessons 必须是数组")
        }
        let base = Calendar.current.startOfDay(for: now)
        return try raw.map { item in
            let subject = try requiredString("subject", in: item)
            let room = try optionalString("room", in: item)
            let teacher = try optionalString("teacher", in: item)
            let startMs = try requiredNumber("startMs", in: item).doubleValue
            let endMs = try requiredNumber("endMs", in: item).doubleValue
            guard endMs > startMs else {
                throw LiveActivityInputError.invalid("课程结束时间必须晚于开始时间")
            }
            return LessonInput(
                subject: subject,
                room: room,
                teacher: teacher,
                start: base.addingTimeInterval(startMs / 1000.0),
                end: base.addingTimeInterval(endMs / 1000.0)
            )
        }
    }

    @available(iOS 16.1, *)
    static func parseState(_ arguments: Any?) throws -> ClassActivityAttributes.ContentState {
        guard let dict = arguments as? [String: Any] else {
            throw LiveActivityInputError.invalid("update 参数必须是对象")
        }
        let subject = try requiredString("subject", in: dict)
        let room = try optionalString("room", in: dict)
        let teacher = try optionalString("teacher", in: dict)
        let phase = try requiredString("phase", in: dict)
        let statusLabel = try requiredString("statusLabel", in: dict)
        let startMs = try requiredNumber("countdownStartEpochMs", in: dict).doubleValue
        let endMs = try requiredNumber("countdownEndEpochMs", in: dict).doubleValue
        guard endMs > startMs else {
            throw LiveActivityInputError.invalid("倒计时结束时间必须晚于开始时间")
        }
        return .init(
            subject: subject,
            room: room,
            teacher: teacher,
            phase: phase,
            statusLabel: statusLabel,
            countdownStart: Date(timeIntervalSince1970: startMs / 1000.0),
            countdownEnd: Date(timeIntervalSince1970: endMs / 1000.0)
        )
    }

    private static func requiredString(_ key: String, in dict: [String: Any]) throws -> String {
        guard let raw = dict[key] as? String else {
            throw LiveActivityInputError.invalid("\(key) 必须是字符串")
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw LiveActivityInputError.invalid("\(key) 不能为空")
        }
        return value
    }

    private static func optionalString(_ key: String, in dict: [String: Any]) throws -> String {
        guard let raw = dict[key] as? String else {
            throw LiveActivityInputError.invalid("\(key) 必须是字符串")
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func requiredNumber(_ key: String, in dict: [String: Any]) throws -> NSNumber {
        guard let value = dict[key] as? NSNumber else {
            throw LiveActivityInputError.invalid("\(key) 必须是数字")
        }
        return value
    }

    private static func flutterError(_ error: Error) -> FlutterError {
        FlutterError(
            code: "invalid_arguments",
            message: error.localizedDescription,
            details: nil
        )
    }
}

enum LiveActivityInputError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        }
    }
}
