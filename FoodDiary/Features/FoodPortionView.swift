import SwiftUI
import NutritionCore

struct FoodPortionView: View {
    @Environment(\.dismiss) private var dismiss
    let food: FoodItem
    let onUpdate: (FoodItem) -> Void
    let onCorrection: (String) -> Void
    let onRemove: () -> Void
    @State private var description = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("当前估算份量", systemImage: "sparkles").font(.caption).foregroundStyle(Theme.accent)
                        Text(food.name).font(.title2.bold())
                        HStack {
                            Text(food.portionLabel).font(.headline).foregroundStyle(.secondary)
                            Spacer()
                            Text("约 \(Theme.number(food.nutrition.calories)) 千卡").font(.headline)
                        }
                        NutritionRow(nutrition: food.nutrition)
                    }
                    .contentCard()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("实际吃了多少？").font(.headline)
                        Text("按上方当前份量调整，热量与营养会一起重算。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            portionButton("吃了一半", multiplier: 0.5, label: "\(food.portionLabel)的一半")
                            portionButton("少一点", multiplier: 0.75, label: "\(food.portionLabel)的四分之三")
                            portionButton("多一点", multiplier: 1.5, label: "\(food.portionLabel)的1.5倍")
                            portionButton("两倍份量", multiplier: 2, label: "\(food.portionLabel)的两倍")
                        }
                    }
                    .contentCard()

                    VStack(alignment: .leading, spacing: 14) {
                        Label("直接告诉 AI", systemImage: "text.bubble").font(.headline)
                        TextField("例如：其实是大碗，汤没有喝", text: $description, axis: .vertical)
                            .lineLimit(3...5)
                            .accessibilityIdentifier("portionDescription")
                        Button("让 AI 重新估算", systemImage: "sparkles") {
                            onCorrection("关于「\(food.name)」：\(description)")
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .contentCard()

                    DisclosureGroup("查看估算依据") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("内部估算重量约 \(Theme.number(food.grams)) 克，实际记录可以直接用份、碗、个来描述。")
                            if !food.notes.isEmpty { Text(food.notes) }
                        }
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                    }
                    .contentCard()
                    if let errorMessage { ErrorNotice(message: errorMessage) }
                    Button("从这餐中移除", role: .destructive) { onRemove(); dismiss() }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("调整份量")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } } }
        }
    }

    private func portionButton(_ title: String, multiplier: Double, label: String) -> some View {
        Button(title) {
            do {
                onUpdate(try food.scaledPortion(by: multiplier, description: label))
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
        .font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity, minHeight: 44)
        .buttonStyle(.bordered)
    }
}
