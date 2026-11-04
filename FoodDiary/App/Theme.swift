import SwiftUI
import NutritionCore

enum Theme {
    static let accent = Color(red: 0.10, green: 0.63, blue: 0.44)
    static let sage = Color(red: 0.43, green: 0.73, blue: 0.52)
    static let carbohydrate = Color(red: 0.96, green: 0.56, blue: 0.36)
    static let fat = Color(red: 0.40, green: 0.55, blue: 0.91)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)

    static func mealColor(_ kind: MealKind) -> Color {
        switch kind {
        case .breakfast: .orange
        case .lunch: Color(red: 0.88, green: 0.63, blue: 0.16)
        case .dinner: .indigo
        case .snack: .pink
        }
    }

    static func number(_ value: Double, decimals: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(0...decimals)))
    }
}

extension View {
    func contentCard() -> some View {
        padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: 26))
    }
}

struct MealIcon: View {
    let kind: MealKind
    var size: CGFloat = 42

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(Theme.mealColor(kind))
            .frame(width: size, height: size)
            .background(Theme.mealColor(kind).opacity(0.12), in: .circle)
            .accessibilityHidden(true)
    }
}

struct NutritionRow: View {
    let nutrition: Nutrition

    var body: some View {
        HStack(spacing: 12) {
            metric("蛋白质", value: nutrition.protein, color: Theme.accent)
            Spacer(minLength: 0)
            metric("碳水", value: nutrition.carbohydrates, color: Theme.carbohydrate)
            Spacer(minLength: 0)
            metric("脂肪", value: nutrition.fat, color: Theme.fat)
        }
        .accessibilityElement(children: .combine)
    }

    private func metric(_ title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: "circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(NutrientLabelStyle(color: color))
            Text("\(Theme.number(value, decimals: 1)) g")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }
}

private struct NutrientLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 6)).foregroundStyle(color)
            configuration.title
        }
    }
}

struct ErrorNotice: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.subheadline)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("errorNotice")
    }
}
