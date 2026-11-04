import SwiftUI
import Charts
import NutritionCore

struct DailyIntakeCard: View {
    let nutrition: Nutrition
    let goal: Double
    let mealCount: Int
    let foodCount: Int
    let date: Date
    let isToday: Bool
    let onDate: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onGoal: () -> Void

    private var progress: Double { goal > 0 ? min(nutrition.calories / goal, 1) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("小食痰记").font(.system(size: 25, weight: .heavy))
                    Button(action: onDate) {
                        Text(date.formatted(.dateTime.month().day().weekday(.wide)))
                            .font(.system(size: 11, weight: .medium))
                    }.buttonStyle(.plain).accessibilityIdentifier("chooseDate")
                }
                Spacer()
                Menu("日期与参考目标", systemImage: "calendar") {
                    Button("前一天", systemImage: "chevron.left", action: onPrevious)
                    Button("选择日期", systemImage: "calendar", action: onDate)
                    Button("后一天", systemImage: "chevron.right", action: onNext).disabled(isToday)
                    Button("设置热量参考", systemImage: "flag", action: onGoal)
                }.labelStyle(.iconOnly).font(.title3).frame(width: 36, height: 36)
            }
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(isToday ? "今日摄入" : "当日摄入").font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.surface.opacity(0.55), in: .capsule)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(Theme.number(nutrition.calories)).font(.system(size: 38, weight: .heavy, design: .rounded))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).accessibilityIdentifier("dailyCalories")
                        Text("千卡").font(.caption.weight(.semibold))
                    }
                    if goal > 0 {
                        Button("参考 \(Theme.number(goal)) 千卡", action: onGoal).font(.system(size: 11)).buttonStyle(.plain)
                        ProgressView(value: progress).tint(Theme.gold).frame(maxWidth: 155)
                        Text(nutrition.calories <= goal ? "还可摄入 \(Theme.number(goal - nutrition.calories)) 千卡" : "超过参考 \(Theme.number(nutrition.calories - goal)) 千卡")
                            .font(.system(size: 12, weight: .semibold))
                    } else {
                        Text("已记录 \(mealCount) 餐 · \(foodCount) 种食物").font(.system(size: 11))
                        Button("设置每日参考", action: onGoal).font(.caption.weight(.semibold)).buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12)
                Image("MilkFrogStanding").resizable().scaledToFit().frame(width: 126, height: 185)
                    .accessibilityHidden(true)
                    .overlay(alignment: .topLeading) {
                        FrogSpeech(text: "吃都吃了，\n先记一笔。")
                            .frame(width: 115).offset(x: -92, y: -9)
                    }
            }
            CompactNutritionStrip(nutrition: nutrition)
        }
        .foregroundStyle(Theme.ink).padding(17)
        .background(Theme.yellowGradient, in: .rect(cornerRadius: 30))
        .animation(.snappy, value: nutrition.calories)
    }
}

struct CompactNutritionStrip: View {
    let nutrition: Nutrition

    var body: some View {
        HStack(spacing: 8) {
            nutrient("蛋白质", value: nutrition.protein, symbol: "leaf.fill", color: Theme.olive)
            Spacer(minLength: 0)
            nutrient("碳水", value: nutrition.carbohydrates, symbol: "flame.fill", color: Theme.gold)
            Spacer(minLength: 0)
            nutrient("脂肪", value: nutrition.fat, symbol: "drop.fill", color: Theme.fat)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.surface.opacity(0.88), in: .rect(cornerRadius: 18))
    }

    private func nutrient(_ title: String, value: Double, symbol: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 10)).foregroundStyle(Theme.mutedInk)
                Text("\(Theme.number(value, decimals: 1)) g").font(.system(size: 15, weight: .bold)).monospacedDigit()
            }
        }.accessibilityElement(children: .combine)
    }
}

struct NutritionDistributionCard: View {
    let nutrition: Nutrition

    private var entries: [MacroEntry] {
        [MacroEntry(title: "蛋白质", grams: nutrition.protein, factor: 4, color: Theme.olive),
         MacroEntry(title: "碳水", grams: nutrition.carbohydrates, factor: 4, color: Theme.accent),
         MacroEntry(title: "脂肪", grams: nutrition.fat, factor: 9, color: Theme.fat)]
    }
    private var totalEnergy: Double { entries.reduce(0) { $0 + $1.energy } }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("营养摄入分布").font(.headline)
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(entries) { entry in
                        Rectangle().fill(entry.color)
                            .frame(width: totalEnergy > 0 ? geometry.size.width * entry.energy / totalEnergy : 0)
                    }
                }.background(Theme.softYellow).clipShape(.capsule)
            }.frame(height: 15).accessibilityHidden(true)
            ForEach(entries) { entry in
                HStack(spacing: 9) {
                    Circle().fill(entry.color).frame(width: 8, height: 8)
                    Text(entry.title).font(.subheadline)
                    Spacer()
                    Text("\(Theme.number(entry.grams, decimals: 1)) g").font(.subheadline.bold()).monospacedDigit()
                    Text(totalEnergy > 0 ? "占 \(Theme.number(entry.energy / totalEnergy * 100))%" : "—")
                        .font(.caption).foregroundStyle(Theme.mutedInk).frame(width: 62, alignment: .trailing)
                }.accessibilityElement(children: .combine)
            }
            Text("供能占比由三大营养素估算，随已记录饮食更新。")
                .font(.caption2).foregroundStyle(Theme.mutedInk)
        }.foregroundStyle(Theme.ink).contentCard()
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
        HStack(alignment: .bottom, spacing: 10) {
            Image("MilkFrogPeek").resizable().scaledToFit().frame(width: 82, height: 115).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("蛙的饮食碎碎念").font(.headline)
                    Spacer()
                    if let score = review?.score { Text("\(score) 分").font(.caption.bold()) }
                }
                Text(review?.summary ?? (recordCount == 0 ? "先记一餐，我再来碎碎念。" : "这顿我记下了，搭配怎么样，咱们一起看看。"))
                    .font(.subheadline).foregroundStyle(Theme.mutedInk).lineLimit(3).lineSpacing(3)
                Button(action: onAction) {
                    HStack(spacing: 7) {
                        if busy { ProgressView() }
                        Text(busy ? "正在回顾…" : (review != nil ? "查看饮食回顾" : (recordCount == 0 ? "开始记餐" : "AI 回顾这一天")))
                        Image(systemName: "arrow.up.right")
                    }.font(.caption.weight(.semibold))
                }.buttonStyle(.glass).disabled(busy)
            }.padding(.vertical, 16)
        }.padding(.horizontal, 16).foregroundStyle(Theme.ink)
            .background(Theme.softGreen, in: .rect(cornerRadius: 24))
    }
}
