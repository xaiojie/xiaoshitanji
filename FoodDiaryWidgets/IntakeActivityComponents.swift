import SwiftUI

struct IntakeActivityCompactCalories: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: IntakeActivityAttributes.ContentState
    let isCurrent: Bool

    private var animate: Bool { !isLuminanceReduced && !reduceMotion && isCurrent }
    private var value: String { isCurrent ? IntakeActivityFormat.number(state.calories) : "待更新" }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 13, weight: .heavy, design: .rounded))
                if isCurrent {
                    Text("千卡").font(.system(size: 8, weight: .medium)).foregroundStyle(.white)
                }
            }
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
        }
        .lineLimit(1)
        .monospacedDigit()
        .foregroundStyle(IntakeActivitySurface.accent)
        .contentTransition(animate ? .numericText() : .identity)
        .animation(animate ? .easeInOut(duration: 0.4) : nil, value: state.calories)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isCurrent ? "今日摄入 \(value) 千卡" : "今日摄入待更新")
    }
}

/// 四餐节点分别来自实际记录，跳过早餐时不会把早餐或连接线点亮。
struct IntakeActivityMeals: View {
    let meals: [DiaryWidgetMeal]?
    let surface: IntakeActivitySurface
    let animate: Bool

    private var kinds: [WidgetMealKind] { WidgetMealKind.allCases }
    private func meal(_ kind: WidgetMealKind) -> DiaryWidgetMeal? { meals?.first { $0.kind == kind } }
    private func isRecorded(_ kind: WidgetMealKind) -> Bool { (meal(kind)?.recordCount ?? 0) > 0 }
    private var transition: Animation? { animate ? .easeInOut(duration: 0.45) : nil }

    var body: some View {
        if meals != nil {
            VStack(spacing: 3) {
                HStack(spacing: 0) {
                    ForEach(kinds.indices, id: \.self) { index in
                        let kind = kinds[index]
                        ZStack {
                            HStack(spacing: 0) {
                                segment(active: index > 0 && isRecorded(kind) && isRecorded(kinds[max(0, index - 1)]))
                                    .opacity(index == 0 ? 0 : 1)
                                segment(active: index + 1 < kinds.count && isRecorded(kind) && isRecorded(kinds[min(kinds.count - 1, index + 1)]))
                                    .opacity(index == kinds.count - 1 ? 0 : 1)
                            }
                            Circle()
                                .fill(isRecorded(kind) ? IntakeActivitySurface.accent : surface.background)
                                .overlay {
                                    Circle().strokeBorder(isRecorded(kind) ? IntakeActivitySurface.accent : surface.secondary, lineWidth: 1.3)
                                }
                                .frame(width: 7, height: 7)
                                .animation(transition, value: isRecorded(kind))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 8)
                .accessibilityHidden(true)
                HStack(spacing: 0) {
                    ForEach(kinds, id: \.rawValue) { kind in
                        HStack(spacing: 3) {
                            Text(kind.title)
                            Text(isRecorded(kind) ? meal(kind).map { IntakeActivityFormat.number($0.calories) } ?? "—" : "待记")
                                .fontWeight(.bold)
                                .foregroundStyle(isRecorded(kind) ? surface.emphasis : surface.secondary)
                                .contentTransition(animate ? .numericText() : .identity)
                        }
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(mealLabel(kind))
                    }
                }
            }
            .animation(transition, value: meals)
        } else {
            Text("打开 App 更新餐次明细")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(surface.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func segment(active: Bool) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(surface.track)
                Rectangle().fill(IntakeActivitySurface.accent)
                    .frame(width: active ? geometry.size.width : 0)
                    .animation(transition, value: active)
            }
        }
        .frame(height: 1.5)
    }

    private func mealLabel(_ kind: WidgetMealKind) -> String {
        guard isRecorded(kind), let meal = meal(kind) else { return "\(kind.title)，尚未记录" }
        return "\(kind.title)，\(IntakeActivityFormat.number(meal.calories)) 千卡，\(meal.recordCount) 条记录"
    }
}

/// 只在饮食事实变化时做一次小幅进入过渡，不启动计时器或循环动画。
struct IntakeActivityFrog: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: IntakeActivityAttributes.ContentState
    let isCurrent: Bool
    let size: CGFloat

    private var animate: Bool { !isLuminanceReduced && !reduceMotion && isCurrent }
    private var revision: IntakeFrogRevision {
        .init(calories: state.calories, mealCount: state.mealCount, meals: state.meals, isCurrent: isCurrent)
    }

    var body: some View {
        ZStack {
            Image("WidgetMilkFrogPeek")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .id(revision)
                .transition(animate
                    ? .asymmetric(insertion: .modifier(active: IntakeFrogArrival(phase: 1),
                                                       identity: IntakeFrogArrival(phase: 0)),
                                  removal: .opacity)
                    : .identity)
        }
        .frame(width: size, height: size)
        .clipped()
        .animation(animate ? .spring(duration: 0.65, bounce: 0.18) : nil, value: revision)
        .accessibilityHidden(true)
    }
}

private struct IntakeFrogRevision: Hashable {
    let calories: Double
    let mealCount: Int
    let meals: [DiaryWidgetMeal]?
    let isCurrent: Bool
}

private struct IntakeFrogArrival: ViewModifier {
    let phase: CGFloat

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(Double(phase) * -4), anchor: .bottom)
            .scaleEffect(1 - phase * 0.04, anchor: .bottom)
            .offset(y: phase * 2)
            .opacity(1 - Double(phase) * 0.2)
    }
}
