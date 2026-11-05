import SwiftUI

enum IntakeWidgetPalette {
    static let ink = Color(red: 0.18, green: 0.15, blue: 0.10)
    static let muted = Color(red: 0.48, green: 0.43, blue: 0.32)
    static let cream = Color(red: 1.00, green: 0.976, blue: 0.914)
    static let olive = Color(red: 0.40, green: 0.51, blue: 0.13)
    static let background = LinearGradient(
        colors: [Color(red: 1.00, green: 0.87, blue: 0.29), Color(red: 1.00, green: 0.79, blue: 0.14)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// 布局独立于 WidgetKit 时间线，数值和图片均为原生视图。
struct IntakeWidgetContent: View {
    let snapshot: DiaryWidgetSnapshot?
    let date: Date
    let compact: Bool

    private var current: DiaryWidgetSnapshot? {
        guard let snapshot, snapshot.isCurrent(on: date) else { return nil }
        return snapshot
    }

    var body: some View {
        GeometryReader { proxy in
            let padding: CGFloat = 12
            let width = max(0, proxy.size.width - padding * 2)
            let height = max(0, proxy.size.height - padding * 2)
            Group {
                if compact { small(width: width, height: height) }
                else { medium(width: width, height: height) }
            }
            .padding(padding)
        }
        .foregroundStyle(IntakeWidgetPalette.ink)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .dynamicTypeSize(.small ... .large)
    }

    private func small(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                heading
                Spacer(minLength: 2)
                Text(mealCount).font(.system(size: 10, weight: .semibold))
            }
            .frame(height: 19)
            HStack(alignment: .center, spacing: 0) {
                calories(size: min(40, height * 0.28))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image("WidgetMilkFrogPeek").resizable().scaledToFit()
                    .frame(width: width * 0.35)
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: 0),
                                               .init(color: .black, location: 0.86),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .accessibilityHidden(true)
            }
            .frame(height: max(35, height - 87))
            Text(goalMessage).font(.system(size: 9.5, weight: .medium))
                .lineLimit(1).minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 11)
            progress(showPercentage: false).frame(height: 5)
            nutrients(compact: true).frame(height: 32)
        }
        .frame(width: width, height: height, alignment: .top)
    }

    private func medium(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 9) {
                heading
                Text(mealCount).font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 3)
                Text(refreshTime).font(.system(size: 9, weight: .medium))
                    .foregroundStyle(IntakeWidgetPalette.muted)
            }.frame(height: 22)
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 5) {
                    HStack(spacing: 8) {
                        calories(size: min(36, height * 0.25))
                            .frame(width: (width - min(88, width * 0.25) - 10) * 0.44, alignment: .leading)
                        Rectangle().fill(IntakeWidgetPalette.ink.opacity(0.12)).frame(width: 1, height: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(targetMessage).font(.system(size: 10, weight: .semibold))
                            Text(goalMessage).font(.system(size: 10))
                        }
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: max(28, min(42, height - 101)))
                    progress(showPercentage: true).frame(height: 10)
                    nutrients(compact: false).frame(height: 34)
                    meals.frame(height: 15)
                }
                VStack(spacing: 4) {
                    Image("WidgetMilkFrogStanding").resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .scaleEffect(1.1, anchor: .bottom)
                        .accessibilityHidden(true)
                    Link(destination: DiaryWidgetRoute.newMeal.url) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                            Text("记一餐").font(.system(size: 12, weight: .bold))
                        }
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).frame(height: 26)
                        .foregroundStyle(IntakeWidgetPalette.cream)
                        .background(IntakeWidgetPalette.ink, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("记一餐，直接打开餐食录入")
                    .accessibilityIdentifier("widgetNewMeal")
                }
                .frame(width: min(88, width * 0.25))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: width, height: height, alignment: .top)
    }

    private var heading: some View {
        Text("今日摄入").font(.system(size: 11, weight: .heavy, design: .rounded))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(IntakeWidgetPalette.cream.opacity(0.85), in: .capsule)
    }

    private func calories(size: CGFloat) -> some View {
        var value = AttributedString(current.map { number($0.calories) } ?? "—")
        value.font = .system(size: size, weight: .heavy, design: .rounded)
        var unit = AttributedString(" 千卡")
        unit.font = .system(size: compact ? 9 : 11, weight: .semibold)
        value += unit
        return Text(value).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progress(showPercentage: Bool) -> some View {
        HStack(spacing: 5) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(IntakeWidgetPalette.cream.opacity(0.85))
                    if let progress = current?.progress {
                        Capsule().fill(IntakeWidgetPalette.ink)
                            .frame(width: proxy.size.width * progress)
                    }
                }
            }
            .frame(height: compact ? 5 : 6)
            .accessibilityHidden(true)
            if showPercentage, let progress = current?.progress {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 9, weight: .semibold)).monospacedDigit()
            }
        }
    }

    private func nutrients(compact: Bool) -> some View {
        HStack(spacing: compact ? 4 : 7) {
            nutrient("蛋白质", value: current?.protein, symbol: "leaf.fill",
                     color: IntakeWidgetPalette.olive, compact: compact)
            divider
            nutrient("碳水", value: current?.carbohydrate, symbol: "flame.fill",
                     color: Color(red: 0.96, green: 0.59, blue: 0.02), compact: compact)
            divider
            nutrient("脂肪", value: current?.fat, symbol: "drop.fill",
                     color: Color(red: 0.66, green: 0.60, blue: 0.14), compact: compact)
        }
        .padding(.horizontal, compact ? 6 : 9)
        .background(IntakeWidgetPalette.cream.opacity(0.92), in: .rect(cornerRadius: compact ? 13 : 16))
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle().fill(IntakeWidgetPalette.ink.opacity(0.12)).frame(width: 0.5, height: 21)
    }

    private func nutrient(_ title: String, value: Double?, symbol: String, color: Color, compact: Bool) -> some View {
        HStack(spacing: compact ? 3 : 5) {
            Image(systemName: symbol).font(.system(size: compact ? 9 : 14, weight: .semibold))
                .foregroundStyle(color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: compact ? 8 : 9, weight: .medium))
                    .foregroundStyle(IntakeWidgetPalette.muted)
                Text(value.map { "\(number($0))g" } ?? "—")
                    .font(.system(size: compact ? 12 : 14, weight: .heavy, design: .rounded))
                    .monospacedDigit()
            }
            .lineLimit(1).minimumScaleFactor(0.65)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var meals: some View {
        if let values = current?.meals {
            HStack(spacing: 5) {
                ForEach(values, id: \.kind) { meal in
                    Text(meal.recordCount > 0 ? "\(meal.kind.title) \(number(meal.calories))" : "\(meal.kind.title)待记")
                        .font(.system(size: 9, weight: meal.recordCount > 0 ? .semibold : .regular))
                        .foregroundStyle(meal.recordCount > 0 ? IntakeWidgetPalette.ink : IntakeWidgetPalette.muted)
                        .lineLimit(1).minimumScaleFactor(0.65)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityLabel("各餐摄入，单位千卡")
        } else {
            Text(current == nil ? "打开 App 更新今日记录" : "打开 App 更新餐次明细")
                .font(.system(size: 9)).foregroundStyle(IntakeWidgetPalette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var mealCount: String {
        guard let current else { return "待更新" }
        return compact ? "\(current.mealCount) 餐" : "已记 \(current.mealCount) 餐"
    }

    private var targetMessage: String {
        guard let value = current?.targetCalories, current?.remaining != nil else { return "未设置目标" }
        return "目标 \(number(value)) 千卡"
    }

    private var goalMessage: String {
        guard let current else { return "打开 App 更新今日记录" }
        guard let remaining = current.remaining else { return compact ? "未设置目标 · 可在 App 中设置" : "打开 App 可设置目标" }
        return remaining >= 0 ? "还可摄入 \(number(remaining)) 千卡" : "已超过 \(number(-remaining)) 千卡"
    }

    private var refreshTime: String {
        guard let current else { return "今日待更新" }
        let time = current.updatedAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        return "\(time) 更新"
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: "zh_CN")))
    }
}
