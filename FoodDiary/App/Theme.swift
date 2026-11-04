import SwiftUI
import NutritionCore

enum Theme {
    static let accent = Color(red: 0.27, green: 0.42, blue: 0.29)
    static let sage = Color(red: 0.56, green: 0.68, blue: 0.49)
    static let carbohydrate = Color(red: 0.54, green: 0.65, blue: 0.45)
    static let fat = Color(red: 0.79, green: 0.58, blue: 0.28)
    static let background = Color(uiColor: .systemGroupedBackground)

    static func number(_ value: Double, decimals: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(0...decimals)))
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
