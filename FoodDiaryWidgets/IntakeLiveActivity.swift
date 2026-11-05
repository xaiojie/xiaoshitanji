import ActivityKit
import SwiftUI
import WidgetKit

struct IntakeLiveActivityWidget: Widget {
    private let ink = Color(red: 0.18, green: 0.15, blue: 0.10)
    private let accent = Color(red: 1.00, green: 0.79, blue: 0.14)
    private let muted = Color(red: 0.48, green: 0.43, blue: 0.32)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IntakeActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(accent)
                .activitySystemActionForegroundColor(ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("今日", systemImage: "fork.knife").font(.caption2).foregroundStyle(muted)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(number(context.state.calories)) 千卡")
                        .font(.caption.weight(.semibold)).foregroundStyle(ink)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.remaining.map { $0 >= 0 ? "还可摄入 \(number($0))" : "超过 \(number(-$0))" } ?? "没设目标")
                            .font(.caption2).foregroundStyle(muted)
                        Text("\(context.state.mealCount) 餐").font(.caption2).foregroundStyle(muted)
                    }
                }
            } compactLeading: {
                Image(systemName: "fork.knife").foregroundStyle(ink)
            } compactTrailing: {
                Text("\(number(context.state.calories))").font(.caption2.weight(.bold)).foregroundStyle(ink)
            } minimal: {
                Image(systemName: "fork.knife").foregroundStyle(ink)
            }
        }
    }

    private func lockScreen(_ context: ActivityViewContext<IntakeActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("今日摄入").font(.caption2.weight(.semibold)).foregroundStyle(muted)
                Text("\(number(context.state.calories)) 千卡").font(.title3.bold()).foregroundStyle(ink)
                Text(context.state.remaining.map {
                    $0 >= 0 ? "还可摄入 \(number($0)) 千卡" : "超过 \(number(-$0)) 千卡"
                } ?? "还没设置能量目标").font(.caption2).foregroundStyle(muted)
            }
            Spacer()
            Text("\(context.state.mealCount) 餐").font(.caption.weight(.semibold)).foregroundStyle(ink)
        }
        .padding(14)
    }

    private func number(_ value: Double) -> String { String(format: "%.0f", value) }
}
