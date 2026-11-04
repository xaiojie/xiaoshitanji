import SwiftUI
import Charts
import NutritionCore

struct DailyIntakeCard: View {
    let nutrition: Nutrition
    let goal: Double
    let mealCount: Int
    let foodCount: Int
    let onGoal: () -> Void

    private var remaining: Double { max(0, goal - nutrition.calories) }
    private var progress: Double { goal > 0 ? min(nutrition.calories / goal, 1) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("饮食摄入", systemImage: "flame").font(.headline)
                Spacer()
                Text("千卡 kcal").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                metric(goal > 0 ? "已摄入" : "已记录", value: goal > 0 ? Theme.number(nutrition.calories) : "\(mealCount)", unit: goal > 0 ? "千卡" : "餐")
                Spacer(minLength: 0)
                ZStack {
                    Circle().stroke(Theme.accent.opacity(0.10), lineWidth: 12)
                    Circle().trim(from: 0, to: progress)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 7) {
                        Text(goal > 0 ? "还可摄入" : "今日摄入").font(.caption).foregroundStyle(.secondary)
                        Text(Theme.number(goal > 0 ? remaining : nutrition.calories))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                            .accessibilityIdentifier("dailyCalories")
                        Text("千卡").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                }
                .frame(width: 148, height: 148)
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                metric("食物种类", value: "\(foodCount)", unit: "种")
            }
            HStack {
                if goal > 0 {
                    Text("参考目标 \(Theme.number(goal)) 千卡").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if nutrition.calories > goal {
                        Text("已记录 \(mealCount) 餐").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("调整", action: onGoal).font(.caption.weight(.medium))
                } else {
                    Text("记录你的饮食，慢慢了解自己").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button("设置目标", action: onGoal).font(.caption.weight(.medium))
                }
            }
        }
        .contentCard()
        .animation(.snappy, value: progress)
    }

    private func metric(_ title: String, value: String, unit: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            Text(unit).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(minWidth: 52)
        .accessibilityElement(children: .combine)
    }
}

struct NutritionDistributionCard: View {
    let nutrition: Nutrition

    private var entries: [MacroEntry] {
        [MacroEntry(title: "碳水", grams: nutrition.carbohydrates, factor: 4, color: Theme.carbohydrate),
         MacroEntry(title: "蛋白质", grams: nutrition.protein, factor: 4, color: Theme.accent),
         MacroEntry(title: "脂肪", grams: nutrition.fat, factor: 9, color: Theme.fat)]
    }
    private var totalEnergy: Double { entries.reduce(0) { $0 + $1.energy } }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label("营养成分", systemImage: "chart.pie").font(.headline)
            HStack(alignment: .top, spacing: 18) {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 9) {
                        Text(entry.title).font(.caption).foregroundStyle(.secondary)
                        Text("\(Theme.number(entry.grams, decimals: 1)) g")
                            .font(.subheadline.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                        ProgressView(value: totalEnergy > 0 ? entry.energy / totalEnergy : 0)
                            .tint(entry.color).accessibilityLabel("\(entry.title)供能占比")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack(spacing: 28) {
                VStack(spacing: 12) {
                    ForEach(entries) { entry in
                        HStack(spacing: 9) {
                            Circle().fill(entry.color).frame(width: 7, height: 7)
                            Text(entry.title).font(.caption)
                            Spacer()
                            Text(totalEnergy > 0 ? "\(Theme.number(entry.energy / totalEnergy * 100))%" : "—")
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                ZStack {
                    if totalEnergy > 0 {
                        Chart(entries) { entry in
                            SectorMark(angle: .value("供能", entry.energy), innerRadius: .ratio(0.70), angularInset: 2)
                                .foregroundStyle(entry.color)
                                .accessibilityLabel(entry.title)
                                .accessibilityValue("\(Theme.number(entry.energy / totalEnergy * 100))%")
                        }
                    } else {
                        Circle().stroke(.quaternary, lineWidth: 14).padding(7)
                    }
                    Text(totalEnergy > 0 ? "供能占比" : "待记录")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .frame(width: 90, height: 90)
            }
            Text("供能占比由三大营养素估算，随饮食记录更新。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .contentCard()
    }
}

private struct MacroEntry: Identifiable {
    let title: String
    let grams: Double
    let factor: Double
    let color: Color
    var id: String { title }
    var energy: Double { grams * factor }
}

struct CoachCard: View {
    let review: DietReview?
    let recordCount: Int
    let busy: Bool
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.title3)
                    .foregroundStyle(Theme.accent).frame(width: 40, height: 40)
                    .background(Theme.accent.opacity(0.10), in: .circle)
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 饮食教练").font(.headline)
                    if let review {
                        Text("基于已记录的 \(review.recordCount) 餐").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("把记录变成下一餐的灵感").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let score = review?.score {
                    VStack(spacing: 3) {
                        Text("\(score)").font(.title2.bold()).foregroundStyle(Theme.accent)
                        Text("AI 参考分").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Text(review?.summary ?? (recordCount == 0
                ? "先记下今天吃了什么，AI 帮你看看营养搭配，给下一餐一点建议。"
                : "今天已记录 \(recordCount) 餐，让 AI 回顾食物搭配、营养分布和可以调整的地方。"))
                .font(.subheadline).foregroundStyle(.secondary).lineSpacing(4).lineLimit(4)
            Button(action: onAction) {
                HStack(spacing: 8) {
                    if busy { ProgressView() }
                    Text(busy ? "正在回顾饮食…" : (review != nil ? "查看饮食回顾" : (recordCount == 0 ? "开始 AI 记餐" : "分析这一天的饮食")))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.subheadline.weight(.semibold))
            }
            .disabled(busy)
        }
        .contentCard()
    }
}
