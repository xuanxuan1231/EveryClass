import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

/// 从 Flutter 下发的一节课（绝对时间）。
struct LessonInput {
    let subject: String
    let room: String
    let teacher: String
    let start: Date
    let end: Date
}

/// 管理课程 Live Activity：持有今日课表，计算当前/下一节，起/更新/结束活动，
/// 并在每节课边界用定时器切换内容。
///
/// 与 Android 前台服务对应；iOS 侧在 App 运行时更新，后台推送（APNs）留待后续。
@available(iOS 16.2, *)
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    private var activity: Activity<ClassActivityAttributes>?
    private var lessons: [LessonInput] = []
    private var timer: Timer?

    /// 应用今日课表并刷新活动。
    func apply(lessons: [LessonInput]) {
        self.lessons = lessons.sorted { $0.start < $1.start }
        refresh()
    }

    /// 结束并移除活动。
    func stop() {
        timer?.invalidate()
        timer = nil
        let ending = activity
        activity = nil
        Task { await ending?.end(nil, dismissalPolicy: .immediate) }
    }

    private func refresh() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let now = Date()
        let current = lessons.first { now >= $0.start && now < $0.end }
        let next = lessons.first { $0.start > now }

        guard let state = makeState(current: current, next: next, now: now) else {
            stop() // 今日无课/已结束
            return
        }

        let content = ActivityContent(state: state, staleDate: state.countdownEnd)
        if let activity = activity {
            Task { await activity.update(content) }
        } else {
            do {
                activity = try Activity.request(
                    attributes: ClassActivityAttributes(),
                    content: content,
                    pushType: nil
                )
            } catch {
                NSLog("[EveryClass] Live Activity 启动失败: \(error.localizedDescription)")
            }
        }
        scheduleNextBoundary(now: now)
    }

    private func makeState(
        current: LessonInput?,
        next: LessonInput?,
        now: Date
    ) -> ClassActivityAttributes.ContentState? {
        if let cur = current {
            return .init(
                subject: cur.subject, room: cur.room, teacher: cur.teacher,
                phase: "上课中", statusLabel: "距下课",
                countdownStart: cur.start, countdownEnd: cur.end
            )
        }
        if let nxt = next {
            return .init(
                subject: nxt.subject, room: nxt.room, teacher: nxt.teacher,
                phase: "下一节", statusLabel: "距上课",
                countdownStart: now, countdownEnd: nxt.start
            )
        }
        return nil
    }

    private func scheduleNextBoundary(now: Date) {
        timer?.invalidate()
        var next: Date?
        for l in lessons {
            if l.start > now { next = min(next ?? l.start, l.start) }
            if l.end > now { next = min(next ?? l.end, l.end) }
        }
        guard let fire = next else { return }
        let interval = max(1, fire.timeIntervalSince(now) + 0.5)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.refresh()
        }
    }
}
