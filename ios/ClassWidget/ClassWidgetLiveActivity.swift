import ActivityKit
import SwiftUI
import WidgetKit

/// 课程 Live Activity 的锁屏视图与灵动岛呈现。
@available(iOS 16.2, *)
struct ClassWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClassActivityAttributes.self) { context in
            // 锁屏 / 横幅
            LockScreenLiveActivityView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.phase)
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(context.state.subject)
                            .font(.headline).lineLimit(1)
                    }
                }
                .contentMargins(.all, 12)
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.statusLabel)
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(
                            timerInterval: context.state.countdownStart...context.state.countdownEnd,
                            countsDown: true
                        )
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 64)
                    }
                }
                .contentMargins(.all, 12)
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.room.isEmpty {
                        Label(context.state.room, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                    }
                }
                .contentMargins(.all, 12)
            } compactLeading: {
                Image(systemName: "book.closed")
                    .frame(width: 52, alignment: .leading)
            } compactTrailing: {
                Text(
                    timerInterval: context.state.countdownStart...context.state.countdownEnd,
                    countsDown: true
                )
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 52, alignment: .trailing)
            } minimal: {
                Image(systemName: "book.closed")
            }
        }
    }
}

@available(iOS 16.2, *)
struct LockScreenLiveActivityView: View {
    let state: ClassActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.phase)
                    .font(.caption).foregroundStyle(.secondary)
                Text(state.subject)
                    .font(.title3).bold().lineLimit(1)
                HStack(spacing: 10) {
                    if !state.room.isEmpty {
                        Label(state.room, systemImage: "mappin.and.ellipse")
                            .font(.footnote)
                    }
                    if !state.teacher.isEmpty {
                        Label(state.teacher, systemImage: "person")
                            .font(.footnote)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(state.statusLabel)
                    .font(.caption2).foregroundStyle(.secondary)
                Text(
                    timerInterval: state.countdownStart...state.countdownEnd,
                    countsDown: true
                )
                .font(.title2).monospacedDigit().bold()
                .frame(maxWidth: 96)
            }
        }
        .padding()
    }
}
