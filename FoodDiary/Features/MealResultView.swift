import SwiftUI
import NutritionCore

struct MealResultView: View {
    @Environment(DiaryModel.self) private var diary
    let record: MealRecord
    let onFood: (FoodItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let photo = diary.photoData(for: record) { ScanPhotoPreview(data: photo, height: 260) }
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("已识别 · 待你确认", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.bold()).foregroundStyle(Theme.olive)
                    Spacer()
                    Image("MilkFrogPeek").resizable().scaledToFit().frame(width: 55, height: 53)
                        .accessibilityHidden(true)
                }
                Text(record.foodNames).font(.headline).lineLimit(2)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(Theme.number(record.nutrition.calories))
                        .font(.system(size: 46, weight: .heavy, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text("千卡 · 估算").font(.caption).foregroundStyle(Theme.mutedInk)
                }
                NutritionRow(nutrition: record.nutrition)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.softYellow, in: .rect(cornerRadius: 26))

            VStack(alignment: .leading, spacing: 14) {
                Text("识别到这些食物").font(.headline)
                ForEach(record.foods) { food in
                    Button { onFood(food) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: food.nutritionLabel == nil ? "fork.knife" : "doc.text.viewfinder")
                                .font(.body).foregroundStyle(Theme.olive)
                                .frame(width: 42, height: 46)
                                .background(Theme.softGreen, in: .rect(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(food.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Text(food.portionLabel).font(.caption).foregroundStyle(.secondary)
                                if let label = food.nutritionLabel {
                                    Label(label.portionIsEstimated ? "营养标签 · 份量估算" : "按营养标签换算", systemImage: "doc.text.viewfinder")
                                        .font(.caption2).foregroundStyle(Theme.olive)
                                }
                                if food.isManual {
                                    Label("手动填写", systemImage: "square.and.pencil")
                                        .font(.caption2).foregroundStyle(Theme.olive)
                                }
                            }
                            Spacer(minLength: 4)
                            Text("约 \(Theme.number(food.nutrition.calories)) 千卡")
                                .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 5).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if food.id != record.foods.last?.id { Divider() }
                }
                if record.foods.isEmpty {
                    Text("用下方的描述补充食物，让 AI 重新计算这一餐。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text("点食物可以改份量、手填营养值，或直接告诉 AI 实际吃了多少。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .contentCard()
        }
        .animation(.snappy, value: record.nutrition.calories)
    }
}

struct MealCorrectionView: View {
    @Binding var text: String
    let busy: Bool
    let onUpdate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("补充一句，AI 来更新", systemImage: "text.bubble").font(.headline)
            TextField("例如：米饭只吃了一半，还有一碗冬瓜汤", text: $text, axis: .vertical)
                .lineLimit(2...5).accessibilityIdentifier("mealCorrection")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["只吃了一半", "还有一碗汤", "这是少油做法"], id: \.self) { example in
                        Button(example) { text = example }.font(.caption).buttonStyle(.bordered)
                    }
                }
            }
            Button("更新这餐的计算", systemImage: "sparkles", action: onUpdate)
                .font(.subheadline.weight(.medium)).yellowAction()
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .contentCard().disabled(busy)
    }
}

struct EstimateExplanationView: View {
    let record: MealRecord

    var body: some View {
        DisclosureGroup("AI 的估算说明") {
            VStack(alignment: .leading, spacing: 12) {
                if !record.summary.isEmpty { Text(record.summary) }
                ForEach(Array(record.assumptions.enumerated()), id: \.offset) { _, assumption in
                    Label(assumption, systemImage: "info.circle")
                }
                if let adjustments = record.adjustments, !adjustments.isEmpty {
                    Text("已修正：\(adjustments.joined(separator: "、"))")
                }
                Text("照片与日常描述会有估算误差，你可以继续描述份量、做法和剩余食物来修正。")
                if !record.originalText.isEmpty { Text("原始描述 \(record.originalText)") }
                if let model = record.model { Text(model).font(.caption2) }
            }
            .font(.caption).foregroundStyle(.secondary).padding(.top, 12)
        }
        .font(.subheadline).contentCard()
    }
}

struct NutritionLabelCard: View {
    let label: NutritionLabel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("营养标签依据", systemImage: "doc.text.viewfinder").font(.headline)
            Text("每 \(Theme.number(label.basisAmount, decimals: 2)) \(label.unit.title)")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.olive)
            LabeledContent("能量", value: "\(Theme.number(label.energy, decimals: 2)) \(label.energyUnit.rawValue)")
            LabeledContent("蛋白质", value: "\(Theme.number(label.protein, decimals: 2)) 克")
            LabeledContent("碳水化合物", value: "\(Theme.number(label.carbohydrates, decimals: 2)) 克")
            LabeledContent("脂肪", value: "\(Theme.number(label.fat, decimals: 2)) 克")
            Divider()
            LabeledContent("本次食用", value: "\(Theme.number(label.consumedAmount, decimals: 2)) \(label.unit.title)")
            Text(label.portionIsEstimated ? "营养值由 AI 读取标签，食用份量含估算。可继续描述净含量和剩余量来修正。" : "营养值由 AI 读取标签，按本次食用量换算。请核对原图和计量单位。")
                .font(.caption).foregroundStyle(.secondary)
            if label.energyUnit == .kilojoules {
                Text("千焦 ÷ 4.184 = 千卡").font(.caption2).foregroundStyle(.secondary)
            }
        }.font(.subheadline).contentCard()
    }
}
