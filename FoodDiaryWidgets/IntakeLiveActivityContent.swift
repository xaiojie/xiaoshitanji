import SwiftUI

enum IntakeActivitySurface: Equatable {
    case island, lockScreen

    static let accent = Color(red: 1, green: 0.79, blue: 0.14)
    var foreground: Color { self == .island ? .white : IntakeWidgetPalette.ink }
    var secondary: Color { self == .island ? .white.opacity(0.72) : IntakeWidgetPalette.muted }
    var emphasis: Color { self == .island ? Self.accent : IntakeWidgetPalette.ink }
    var track: Color { foreground.opacity(self == .island ? 0.20 : 0.12) }
    var background: Color { self == .island ? .black : IntakeWidgetPalette.cream }
}

enum IntakeActivityFormat {
    static func number(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: "zh_CN")))
    }

    static func grams(_ value: Double?) -> String {
        value.map { "\(number($0))g" } ?? "—"
    }
}

/// 第三套「餐次进度」：系统负责岛的轮廓和相机避让，内容只占可用区域。
struct IntakeLiveActivityContent: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: IntakeActivityAttributes.ContentState
    let isStale: Bool
    let surface: IntakeActivitySurface

    private var current: Bool { !isStale && state.isCurrent(on: .now) }
    private var progress: Double? { current ? state.progress : nil }
    private var animation: Animation? {
        isLuminanceReduced || reduceMotion ? nil : .easeInOut(duration: 0.45)
    }

    var body: some View {
        content
            .foregroundStyle(surface.foreground)
            .background {
                if surface == .lockScreen {
                    LinearGradient(colors: [Color(red: 1, green: 0.92, blue: 0.64), IntakeWidgetPalette.cream],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .dynamicTypeSize(.small ... .large)
    }

    @ViewBuilder
    private var content: some View {
        if surface == .lockScreen {
            lockScreenBody
        } else {
            islandBody
        }
    }

    /// 实时活动只放三餐：加餐写在 App 和桌面小组件里。
    private var liveActivityKinds: [WidgetMealKind] { WidgetMealKind.liveActivityKinds }

    /// 岛上的固定高度正好等于四行内容加行距，避免最后一行被裁掉。
    private var islandBody: some View {
        VStack(spacing: 3) {
            energyRow.frame(height: 38)
            energyProgress.frame(height: 7)
            IntakeActivityMeals(meals: current ? state.meals : nil, surface: .island,
                                animate: animation != nil, kinds: liveActivityKinds)
                .frame(height: 26)
            islandFooter.frame(height: 24)
        }
        .frame(height: 104)
    }

    private var lockScreenBody: some View {
        VStack(spacing: 4) {
            lockScreenHeading.frame(height: 54)
            energyProgress.frame(height: 8)
            IntakeActivityMeals(meals: current ? state.meals : nil, surface: .lockScreen,
                                animate: animation != nil, kinds: liveActivityKinds)
                .frame(height: 30)
            footer.frame(height: 28)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(height: 160)
    }

    private var islandFooter: some View {
        HStack(spacing: 6) {
            Text(nutrientsText)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(surface.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(nutrientsAccessibility)
            Link(destination: DiaryWidgetRoute.newMeal.url) {
                HStack(spacing: 3) {
                    Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                    Text("记一餐").font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 10)
                .frame(height: 24)
                .foregroundStyle(IntakeWidgetPalette.ink)
                .background(IntakeActivitySurface.accent, in: .capsule)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("记一餐，直接打开餐食录入")
            .accessibilityIdentifier("liveActivityNewMeal")
        }
    }

    private var lockScreenHeading: some View {
        HStack(spacing: 8) {
            IntakeActivityFrog(state: state, isCurrent: current, size: 50)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(current ? "今日饮食" : "今日待更新")
                    Spacer(minLength: 4)
                    Text(current ? "已记 \(state.mealCount) 餐" : "打开 App 刷新")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(surface.secondary)
                .lineLimit(1)
                energyRow
            }
        }
    }

    private var energyRow: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(current ? IntakeActivityFormat.number(state.calories) : "—")
                    .font(.system(size: surface == .island ? 31 : 30, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(animation == nil ? .identity : .numericText())
                    .animation(animation, value: state.calories)
                Text("千卡").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(surface.emphasis)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .layoutPriority(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(current ? "今日摄入 \(IntakeActivityFormat.number(state.calories)) 千卡" : "今日摄入待更新")
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Text(targetText).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(surface.secondary)
                Text(remainingText).font(.system(size: 11, weight: .semibold))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
    }

    private var targetText: String {
        guard current else { return "记录已过期" }
        guard state.remaining != nil, let target = state.targetCalories else { return "未设置目标" }
        return "目标 \(IntakeActivityFormat.number(target))"
    }

    private var remainingText: String {
        guard current else { return "打开 App 更新" }
        guard let remaining = state.remaining else { return "仅显示已记摄入" }
        return remaining >= 0
            ? "剩余 \(IntakeActivityFormat.number(remaining)) 千卡"
            : "超出 \(IntakeActivityFormat.number(-remaining)) 千卡"
    }

    private var energyProgress: some View {
        HStack(spacing: 5) {
            if let progress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(surface.track)
                        Capsule().fill(surface.emphasis)
                            .frame(width: max(0, geometry.size.width * progress))
                            .animation(animation, value: progress)
                    }
                }
                .frame(height: 5)
                .accessibilityHidden(true)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 8, weight: .semibold))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.map { "目标进度 \(Int(($0 * 100).rounded())) 百分比" } ?? "未设置能量目标")
        .accessibilityHidden(progress == nil)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(nutrientsText)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(nutrientsAccessibility)
            Link(destination: DiaryWidgetRoute.newMeal.url) {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                    Text("记一餐").font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .foregroundStyle(surface == .island ? IntakeWidgetPalette.ink : IntakeWidgetPalette.cream)
                .background(surface == .island ? IntakeActivitySurface.accent : IntakeWidgetPalette.ink, in: .capsule)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("记一餐，直接打开餐食录入")
            .accessibilityIdentifier("liveActivityNewMeal")
        }
        .overlay(alignment: .top) {
            Rectangle().fill(surface.track).frame(height: 0.5).offset(y: -3)
                .accessibilityHidden(true)
        }
    }

    private var nutrientsText: String {
        guard current else { return "打开 App 更新今日记录" }
        return "蛋白质 \(IntakeActivityFormat.grams(state.protein)) · 碳水 \(IntakeActivityFormat.grams(state.carbohydrate)) · 脂肪 \(IntakeActivityFormat.grams(state.fat))"
    }

    private var nutrientsAccessibility: String {
        guard current else { return nutrientsText }
        func description(_ value: Double?) -> String {
            value.map { "\(IntakeActivityFormat.number($0)) 克" } ?? "待更新"
        }
        return "蛋白质 \(description(state.protein))，碳水 \(description(state.carbohydrate))，脂肪 \(description(state.fat))"
    }
}
