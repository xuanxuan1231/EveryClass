import ActivityKit
import Foundation

/// Live Activity 的数据模型，App 与 Widget Extension 两个 target 共享。
///
/// 本文件同时编译进 Runner 与 ClassWidget 两个 target。
@available(iOS 16.1, *)
struct ClassActivityAttributes: ActivityAttributes {
    public typealias ContentState = State

    /// 随时间变化的动态内容。
    public struct State: Codable, Hashable {
        public var subject: String
        public var room: String
        public var teacher: String
        /// 阶段文案，如"上课中" / "下一节"。
        public var phase: String
        /// 倒计时说明，如"距下课" / "距上课"。
        public var statusLabel: String
        /// 原生倒计时区间：从 [countdownStart] 到 [countdownEnd]。
        public var countdownStart: Date
        public var countdownEnd: Date

        public init(
            subject: String,
            room: String,
            teacher: String,
            phase: String,
            statusLabel: String,
            countdownStart: Date,
            countdownEnd: Date
        ) {
            self.subject = subject
            self.room = room
            self.teacher = teacher
            self.phase = phase
            self.statusLabel = statusLabel
            self.countdownStart = countdownStart
            self.countdownEnd = countdownEnd
        }
    }

    public init() {}
}
