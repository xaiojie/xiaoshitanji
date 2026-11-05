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
    @State private var editingManually = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("当前估算份量", systemImage: "sparkles").font(.caption).foregroundStyle(Theme.olive)
                        Text(food.name).font(.title2.bold())
                        HStack {
                            Text(food.portionLabel).font(.headline).foregroundStyle(.secondary)
                            Spacer()
                            Text("约 \(Theme.number(food.nutrition.calories)) 千卡").font(.headline)
                        }
                        NutritionRow(nutrition: food.nutrition)
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.softYellow, in: .rect(cornerRadius: 26))

                    if let label = food.nutritionLabel { NutritionLabelCard(label: label) }

                    if !sizeSuggestions.isEmpty || PackagedSizes.isSoupy(food.name) {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("按整包记更准", systemImage: "shippingbox").font(.headline)
                            Text("标签只写每 \(Theme.number(labelBasis, decimals: 2)) \(labelUnit) 的营养时，整包的量要自己选。选完热量会一起重算。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if !sizeSuggestions.isEmpty {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    ForEach(sizeSuggestions) { size in
                                        Button(size.title) { apply(size) }
                                            .font(.subheadline.weight(.medium))
                                            .buttonStyle(.glass)
                                            .accessibilityIdentifier("packageSize\(Int(size.amount))")
                                    }
                                }
                            }
                            if PackagedSizes.isSoupy(food.name) {
                                Button("汤没喝，按 90% 算", systemImage: "drop.triangle") {
                                    do {
                                        onUpdate(try food.scaledPortion(by: PackagedSizes.withoutSoupRatio, description: "汤没喝，按 90% 计"))
                                        dismiss()
                                    } catch { errorMessage = error.localizedDescription }
                                }
                                .font(.subheadline.weight(.medium))
                                .buttonStyle(.glass)
                                .accessibilityIdentifier("withoutSoup")
                            }
                        }
                        .contentCard()
                    }

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
                        Label("知道准确数值？", systemImage: "square.and.pencil").font(.headline)
                        Text("直接改写这一项的热量与营养，会标记为手动填写，不再使用 AI 估算。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("直接修改营养值", systemImage: "square.and.pencil") { editingManually = true }
                            .yellowAction()
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
                        .yellowAction()
                        .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .contentCard()

                    DisclosureGroup("查看估算依据") {
                        VStack(alignment: .leading, spacing: 8) {
                            if food.nutritionLabel == nil {
                                Text("内部估算重量约 \(Theme.number(food.grams)) 克，实际记录可以直接用份、碗、个来描述。")
                            }
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
            .toolbar(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } } }
            .sheet(isPresented: $editingManually) {
                ManualFoodView(editing: food) { updated in
                    onUpdate(updated)
                    dismiss()
                }
            }
        }
    }

    private var labelBasis: Double { food.nutritionLabel?.basisAmount ?? 100 }
    private var labelUnit: String { food.nutritionLabel?.unit.title ?? "克" }

    /// 只提供和标签计量单位一致的候选（克对克、毫升对毫升）。
    private var sizeSuggestions: [PackageSizeSuggestion] {
        guard let label = food.nutritionLabel else { return [] }
        return PackagedSizes.suggestions(for: food.name).filter { $0.unit == label.unit }
    }

    private func apply(_ size: PackageSizeSuggestion) {
        guard let label = food.nutritionLabel else { return }
        var updated = food
        updated.nutritionLabel = label.withConsumedAmount(size.amount)
        if size.unit == .grams { updated.grams = size.amount }
        onUpdate(updated)
        dismiss()
    }

    private func portionButton(_ title: String, multiplier: Double, label: String) -> some View {
        Button {
            do {
                onUpdate(try food.scaledPortion(by: multiplier, description: label))
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        } label: { Text(title).frame(maxWidth: .infinity, minHeight: 40) }
        .font(.subheadline.weight(.medium))
        .buttonStyle(.glass)
    }
}
