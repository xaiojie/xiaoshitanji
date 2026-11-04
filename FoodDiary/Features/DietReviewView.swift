import SwiftUI
import NutritionCore

struct DietReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let review: DietReview
    let onRefresh: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("AI 饮食回顾", systemImage: "sparkles").font(.subheadline).foregroundStyle(Theme.olive)
                        Text(review.date.formatted(.dateTime.month().day().weekday())).font(.title2.bold())
                        if let score = review.score {
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(score)").font(.system(size: 56, weight: .bold, design: .rounded)).foregroundStyle(Theme.olive)
                                Text("AI 参考分").font(.subheadline).foregroundStyle(.secondary)
                            }
                        } else {
                            Text("本次暂未评分").font(.headline).foregroundStyle(.secondary)
                        }
                        Text(review.summary).font(.body).lineSpacing(5)
                        Text("仅覆盖已记录的 \(review.recordCount) 餐")
                            .font(.caption).foregroundStyle(.secondary)
                        if let goal = review.calorieGoal {
                            Text("分析时的参考目标 \(Theme.number(goal)) 千卡")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contentCard()
                    if !review.highlights.isEmpty {
                        ReviewAdviceCard(title: "今天的亮点", symbol: "checkmark.seal", items: review.highlights, color: Theme.olive)
                    }
                    if !review.suggestions.isEmpty {
                        ReviewAdviceCard(title: "下一餐可以试试", symbol: "leaf", items: review.suggestions, color: Theme.olive)
                    }
                    Text("回顾依据已保存的饮食和 AI 营养估算生成。补记或修改餐食后，可重新分析。")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
                    Text("生成于 \(review.generatedAt.formatted(.dateTime.month().day().hour().minute())) · \(review.model)")
                        .font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 4)
                    Button("重新分析这一天", systemImage: "arrow.clockwise") { dismiss(); onRefresh() }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("饮食回顾").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

private struct ReviewAdviceCard: View {
    let title: String
    let symbol: String
    let items: [String]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(color)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(color).frame(width: 6, height: 6).padding(.top, 7)
                    Text(item).font(.subheadline).lineSpacing(4)
                }
            }
        }
        .contentCard()
    }
}
