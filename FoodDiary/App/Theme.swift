import SwiftUI
import NutritionCore

enum Theme {
    static let accent = Color(red: 1.00, green: 0.79, blue: 0.14)
    static let gold = Color(red: 0.96, green: 0.64, blue: 0.04)
    static let ink = Color(red: 0.18, green: 0.15, blue: 0.10)
    static let mutedInk = Color(red: 0.48, green: 0.43, blue: 0.32)
    static let olive = Color(red: 0.40, green: 0.51, blue: 0.13)
    static let sage = Color(red: 0.67, green: 0.77, blue: 0.33)
    static let carbohydrate = accent
    static let fat = Color(red: 0.66, green: 0.60, blue: 0.14)
    static let background = Color(red: 1.00, green: 0.976, blue: 0.914)
    static let surface = Color(red: 1.00, green: 0.988, blue: 0.950)
    static let softYellow = Color(red: 1.00, green: 0.93, blue: 0.67)
    static let softGreen = Color(red: 0.91, green: 0.95, blue: 0.75)
    static let darkSurface = Color(red: 0.19, green: 0.16, blue: 0.11)
    static let yellowGradient = LinearGradient(colors: [Color(red: 1, green: 0.87, blue: 0.29), accent],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
    static let darkGradient = LinearGradient(colors: [Color(red: 0.25, green: 0.21, blue: 0.14), darkSurface],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)

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
            .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(Theme.gold.opacity(0.08), lineWidth: 1) }
    }

    func yellowAction() -> some View {
        buttonStyle(.glassProminent).tint(Theme.accent).foregroundStyle(Theme.ink)
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
            metric("蛋白质", value: nutrition.protein, color: Theme.olive)
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
