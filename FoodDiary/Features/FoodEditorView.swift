import SwiftUI
import NutritionCore

struct FoodEditorView: View {
    @Environment(\.dismiss) private var dismiss
    private let original: FoodItem
    private let onSave: (FoodItem) -> Void
    @State private var name: String
    @State private var grams: String
    @State private var calories: String
    @State private var protein: String
    @State private var carbohydrates: String
    @State private var fat: String
    @State private var notes: String
    @State private var errorMessage: String?

    init(food: FoodItem, onSave: @escaping (FoodItem) -> Void) {
        original = food
        self.onSave = onSave
        _name = State(initialValue: food.name)
        _grams = State(initialValue: Self.editableNumber(food.grams))
        _calories = State(initialValue: food.name.isEmpty ? "" : Self.editableNumber(food.per100g.calories))
        _protein = State(initialValue: Self.editableNumber(food.per100g.protein))
        _carbohydrates = State(initialValue: Self.editableNumber(food.per100g.carbohydrates))
        _fat = State(initialValue: Self.editableNumber(food.per100g.fat))
        _notes = State(initialValue: food.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("食物与实际食用量") {
                    TextField("食物名称", text: $name).accessibilityIdentifier("foodName")
                    numericField("实际吃下", unit: "克", text: $grams, identifier: "foodGrams")
                }
                Section {
                    numericField("热量", unit: "千卡", text: $calories, identifier: "foodCalories")
                    numericField("蛋白质", unit: "克", text: $protein, identifier: "foodProtein")
                    numericField("碳水化合物", unit: "克", text: $carbohydrates, identifier: "foodCarbs")
                    numericField("脂肪", unit: "克", text: $fat, identifier: "foodFat")
                } header: {
                    Text("每 100 克的营养")
                } footer: {
                    Text("可参考包装上的每 100 克营养标签。调整上方食用重量时，会按比例重新计算这一份的营养。")
                }
                if let food = try? makeFood() {
                    Section("这一份合计") {
                        LabeledContent("热量", value: "\(Theme.number(food.nutrition.calories)) 千卡")
                        NutritionRow(nutrition: food.nutrition).padding(.vertical, 6)
                    }
                }
                Section("备注") {
                    TextField("例如熟重、去皮或少油", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                if let errorMessage { Section { ErrorNotice(message: errorMessage) } }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(original.name.isEmpty ? "添加食物" : "调整食物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: save)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("saveFood")
                }
            }
        }
    }

    private func numericField(_ title: String, unit: String, text: Binding<String>, identifier: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 65, maxWidth: 130)
                .accessibilityLabel("\(title)，\(unit)")
                .accessibilityIdentifier(identifier)
            Text(unit).foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
        }
    }

    private func makeFood() throws -> FoodItem {
        let fields = [grams, calories, protein, carbohydrates, fat]
        let values = fields.compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard values.count == 5 else {
            throw DiaryError.invalidInput("请在重量和营养栏中填写有效数字，热量为零时请填 0。")
        }
        var food = original
        food.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        food.grams = values[0]
        food.per100g = Nutrition(calories: values[1], protein: values[2], carbohydrates: values[3], fat: values[4])
        food.notes = notes
        try food.validate()
        return food
    }

    private func save() {
        do {
            onSave(try makeFood())
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private static func editableNumber(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(0...3)))
    }
}
