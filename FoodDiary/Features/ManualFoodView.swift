import SwiftUI
import NutritionCore

/// 不经过 AI 的手动录入：用户直接填写这一份吃下的热量与营养。
struct ManualFoodView: View {
    @Environment(\.dismiss) private var dismiss
    let editing: FoodItem?
    let onSave: (FoodItem) -> Void
    @State private var input: ManualFoodInput
    @State private var errorMessage: String?

    init(editing: FoodItem? = nil, onSave: @escaping (FoodItem) -> Void) {
        self.editing = editing
        self.onSave = onSave
        _input = State(initialValue: editing.map { ManualFoodInput(food: $0) } ?? ManualFoodInput())
    }

    private var isEditing: Bool { editing != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 16) {
                        Label(isEditing ? "改写这一项的营养值" : "直接填写，不用等 AI", systemImage: "square.and.pencil")
                            .font(.caption).foregroundStyle(Theme.olive)
                        TextField("食物名称，例如：鸡胸肉沙拉", text: $input.name)
                            .font(.title3.weight(.semibold))
                            .accessibilityIdentifier("manualFoodName")
                        TextField("份量描述，例如：一份、一碗", text: $input.portionDescription)
                            .foregroundStyle(.secondary)
                        Divider()
                        numberRow(title: "克数", text: $input.gramsText, unit: "克", prompt: "留空按 100 克")
                        numberRow(title: "这一份热量", text: $input.caloriesText, unit: "千卡", prompt: "必填")
                        HStack(spacing: 10) {
                            macroField("蛋白质", text: $input.proteinText)
                            macroField("碳水", text: $input.carbohydratesText)
                            macroField("脂肪", text: $input.fatText)
                        }
                    }
                    .contentCard()

                    Text("填的是「这一份吃下的总量」，克数只用于以后按份量缩放。手填记录不请求 AI，离线也能用。")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)

                    if let errorMessage { ErrorNotice(message: errorMessage) }
                }
                .padding(20)
            }
            .background(Theme.background)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "修改营养值" : "手动填写")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Label(isEditing ? "更新这一项" : "加入这一餐", systemImage: "checkmark")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .yellowAction()
                .disabled(input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || input.caloriesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("saveManualFood")
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Theme.background)
            }
        }
    }

    private func numberRow(title: String, text: Binding<String>, unit: String, prompt: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            TextField(prompt, text: text)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(maxWidth: 130)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func macroField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(Theme.mutedInk)
            HStack(spacing: 4) {
                TextField("0", text: text).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                Text("克").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Theme.softYellow.opacity(0.45), in: .rect(cornerRadius: 14))
    }

    private func save() {
        do {
            var food = try input.food()
            if let editing { food.id = editing.id }
            onSave(food)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
