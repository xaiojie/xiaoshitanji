import SwiftUI
import NutritionCore

struct MealResultView: View {
    let record: MealRecord
    let onFood: (FoodItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("这一餐的估算", systemImage: "sparkles").font(.subheadline).foregroundStyle(Theme.accent)
                    Spacer()
                    Text("\(record.foods.count) 种食物").font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(Theme.number(record.nutrition.calories))
                        .font(.system(size: 48, weight: .semibold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text("千卡").foregroundStyle(.secondary)
                }
                NutritionRow(nutrition: record.nutrition)
            }
            .contentCard()

            VStack(alignment: .leading, spacing: 14) {
                Text("识别到这些食物").font(.headline)
                ForEach(record.foods) { food in
                    Button { onFood(food) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "fork.knife")
                                .font(.body).foregroundStyle(Theme.accent)
                                .frame(width: 42, height: 46)
                                .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(food.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Text(food.portionLabel).font(.caption).foregroundStyle(.secondary)
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
                Text("点食物可以选择吃了一半、少一点，或直接告诉 AI 实际吃了多少。")
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
            Button("重新分析这一餐", systemImage: "sparkles", action: onUpdate)
                .font(.subheadline.weight(.medium)).buttonStyle(.borderedProminent)
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
                if let data = record.photoJPEG, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                        .clipShape(.rect(cornerRadius: 14))
                }
                if let model = record.model { Text(model).font(.caption2) }
            }
            .font(.caption).foregroundStyle(.secondary).padding(.top, 12)
        }
        .font(.subheadline).contentCard()
    }
}
