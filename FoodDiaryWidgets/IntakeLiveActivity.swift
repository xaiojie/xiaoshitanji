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
                // 相机两侧只放奶蛙和「记一餐」；主要数据在 bottom，不覆盖硬件区域。
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        IntakeActivityFrog(state: context.state, isCurrent: current, size: 26)
                        Text(current ? "今日" : "待更新")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if current {
                        Link(destination: DiaryWidgetRoute.newMeal.url) {
                            HStack(spacing: 3) {
                                Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                                Text("记一餐").font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .foregroundStyle(IntakeWidgetPalette.ink)
                            .background(IntakeActivitySurface.accent, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .accessibilityLabel("记一餐，直接打开餐食录入")
                        .accessibilityIdentifier("liveActivityNewMeal")
                    } else {
                        Text("打开 App 更新")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
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
