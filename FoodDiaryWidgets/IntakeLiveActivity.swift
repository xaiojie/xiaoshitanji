import ActivityKit
import SwiftUI
import WidgetKit

struct IntakeLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IntakeActivityAttributes.self) { context in
            IntakeLiveActivityContent(state: context.state, isStale: context.isStale, surface: .lockScreen)
                .activityBackgroundTint(IntakeActivitySurface.lockScreen.background)
                .activitySystemActionForegroundColor(IntakeWidgetPalette.ink)
                .widgetURL(DiaryWidgetRoute.today.url)
        } dynamicIsland: { context in
            let current = !context.isStale && context.state.isCurrent(on: .now)
            return DynamicIsland {
                // 相机两侧只放奶蛙和餐数；主要数据在 bottom，不覆盖硬件区域。
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        IntakeActivityFrog(state: context.state, isCurrent: current, size: 26)
                        Text(current ? "今日" : "待更新")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(current ? "已记 \(context.state.mealCount) 餐" : "打开 App 更新")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(height: 26)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IntakeLiveActivityContent(state: context.state, isStale: context.isStale, surface: .island)
                }
            } compactLeading: {
                IntakeActivityFrog(state: context.state, isCurrent: current, size: 26)
            } compactTrailing: {
                IntakeActivityCompactCalories(state: context.state, isCurrent: current)
            } minimal: {
                ZStack(alignment: .topTrailing) {
                    IntakeActivityFrog(state: context.state, isCurrent: current, size: 24)
                    Circle().fill(current ? IntakeActivitySurface.accent : .gray)
                        .frame(width: 4, height: 4)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(current ? "小食痰记，今日已记 \(context.state.mealCount) 餐" : "小食痰记，今日待更新")
            }
            .widgetURL(DiaryWidgetRoute.today.url)
            .keylineTint(IntakeActivitySurface.accent)
        }
    }

}
