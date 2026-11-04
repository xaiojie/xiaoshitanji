import SwiftUI
import Charts
import NutritionCore

struct TrendsView: View {
    @Environment(DiaryModel.self) private var diary
    @State private var dayCount = 7

    private var days: [TrendDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (-(dayCount - 1)...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return TrendDay(date: date, nutrition: diary.document.total(on: date),
                            count: diary.document.records(on: date).count,
                            score: diary.document.review(on: date)?.score)
        }
    }

    private var recordedDays: [TrendDay] { days.filter { $0.count > 0 } }
    private var scoredDays: [TrendDay] { days.filter { $0.score != nil } }
    private var average: Nutrition {
        guard !recordedDays.isEmpty else { return .zero }
        return recordedDays.reduce(Nutrition.zero) { $0 + $1.nutrition }.scaled(by: 1 / Double(recordedDays.count))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("从每一餐，看见饮食习惯")
                        .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 4)
                    Picker("统计范围", selection: $dayCount) {
                        Text("最近 7 天").tag(7)
                        Text("最近 30 天").tag(30)
                    }
                    .pickerStyle(.segmented)
                    if let error = diary.loadError {
                        ErrorNotice(message: error).contentCard()
                    } else {
                        HStack {
                            metric("记录天数", value: "\(recordedDays.count)", unit: "/ \(dayCount) 天")
                            Spacer()
                            metric("饮食记录", value: "\(days.reduce(0) { $0 + $1.count })", unit: "餐")
                            Spacer()
                            metric("AI 回顾", value: "\(days.filter { diary.document.review(on: $0.date) != nil }.count)", unit: "天")
                        }
                        .padding(.horizontal, 12).padding(.vertical, 14)
                        calorieChart
                        scoreChart
                        if !recordedDays.isEmpty {
                            Text("记录日平均营养").font(.title3.bold()).padding(.horizontal, 4).padding(.top, 8)
                            NutritionDistributionCard(nutrition: average)
                            dayList
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("饮食趋势")
        }
    }

    private var calorieChart: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("饮食摄入", systemImage: "flame").font(.headline)
            if recordedDays.isEmpty {
                TrendEmptyView(symbol: "chart.bar", title: "从第一餐开始积累", detail: "拍照或描述吃了什么，摄入趋势会在这里慢慢呈现。")
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text("记录日平均").font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Theme.number(average.calories)).font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("千卡 / 天").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Chart(days) { day in
                    BarMark(x: .value("日期", day.date, unit: .day), y: .value("千卡", day.nutrition.calories))
                        .foregroundStyle(Theme.accent).cornerRadius(4)
                        .accessibilityLabel(day.date.formatted(.dateTime.month().day()))
                        .accessibilityValue(day.count == 0 ? "未记录" : "\(Theme.number(day.nutrition.calories)) 千卡")
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: dayCount == 7 ? 1 : 5)) { _ in
                        AxisValueLabel(format: dayCount == 7 ? .dateTime.weekday(.narrow) : .dateTime.month().day())
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 190)
                .accessibilityLabel("最近\(dayCount)天饮食摄入，单位千卡")
                Text("只按有记录的日期计算均值，当天未记完时数值仍会更新。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contentCard()
    }

    private var scoreChart: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("AI 饮食搭配评分", systemImage: "sparkles").font(.headline)
            if scoredDays.isEmpty {
                TrendEmptyView(symbol: "leaf", title: "等待一次饮食回顾", detail: "在饮食首页让 AI 回顾已记录的餐食，信息足够时生成参考评分。")
            } else {
                let scores = scoredDays.compactMap(\.score)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Theme.number(Double(scores.reduce(0, +)) / Double(scores.count)))
                        .font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(Theme.accent)
                    Text("平均分").font(.caption).foregroundStyle(.secondary)
                }
                Chart(scoredDays) { day in
                    if let score = day.score {
                        PointMark(x: .value("日期", day.date, unit: .day), y: .value("评分", score))
                            .foregroundStyle(Theme.accent).symbolSize(55)
                            .accessibilityLabel(day.date.formatted(.dateTime.month().day()))
                            .accessibilityValue("\(score) 分")
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: dayCount == 7 ? 1 : 5)) { _ in AxisValueLabel(format: .dateTime.day()) } }
                .chartYAxis { AxisMarks(position: .leading, values: [0, 50, 100]) }
                .frame(height: 160)
                .accessibilityLabel("AI 饮食搭配参考分，范围零至一百分")
                Text("评分基于当时的参考目标与已记录餐食，信息不足的日期保留空缺。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contentCard()
    }

    private var dayList: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("每日记录").font(.headline)
            ForEach(days.reversed()) { day in
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(day.date.formatted(.dateTime.month().day().weekday())).font(.subheadline)
                        Text(day.count == 0 ? "未记录" : "已记录 \(day.count) 餐").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(day.count == 0 ? "—" : "\(Theme.number(day.nutrition.calories)) 千卡")
                        .font(.subheadline.weight(.medium)).monospacedDigit()
                }
                if day.id != days.first?.id { Divider() }
            }
        }
        .contentCard()
    }

    private func metric(_ title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.title2.bold()).monospacedDigit()
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TrendDay: Identifiable {
    let date: Date
    let nutrition: Nutrition
    let count: Int
    let score: Int?
    var id: Date { date }
}

private struct TrendEmptyView: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 32)).foregroundStyle(Theme.sage)
            Text(title).font(.subheadline.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(3)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 25)
    }
}
