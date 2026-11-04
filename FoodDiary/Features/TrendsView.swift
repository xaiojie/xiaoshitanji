import SwiftUI
import Charts
import NutritionCore

struct TrendsView: View {
    @Environment(DiaryModel.self) private var diary

    private var days: [TrendDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let records = diary.document.records(on: date)
            return TrendDay(date: date, nutrition: diary.document.total(on: date), count: records.count)
        }
    }

    private var recordedDays: [TrendDay] { days.filter { $0.count > 0 } }
    private var average: Double {
        guard !recordedDays.isEmpty else { return 0 }
        return recordedDays.reduce(0) { $0 + $1.nutrition.calories } / Double(recordedDays.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    Text("最近 7 天").font(.subheadline).foregroundStyle(.secondary)
                    if let error = diary.loadError {
                        ErrorNotice(message: error)
                    } else if recordedDays.isEmpty {
                        ContentUnavailableView("趋势从第一餐开始", systemImage: "chart.bar.xaxis", description: Text("记录饮食后，在这里回看每天的摄入。"))
                            .padding(.top, 70)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("记录日平均摄入").font(.subheadline).foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline) {
                                Text(Theme.number(average))
                                    .font(.system(size: 52, weight: .medium, design: .rounded)).monospacedDigit()
                                Text("千卡 / 天").foregroundStyle(.secondary)
                            }
                            Text("7 天内记录了 \(recordedDays.count) 天，\(days.reduce(0) { $0 + $1.count }) 餐")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Chart(days) { day in
                            BarMark(x: .value("日期", day.date, unit: .day), y: .value("千卡", day.nutrition.calories))
                                .foregroundStyle(Theme.sage)
                                .cornerRadius(5)
                                .accessibilityLabel(day.date.formatted(.dateTime.month().day()))
                                .accessibilityValue(day.count == 0 ? "未记录" : "\(Theme.number(day.nutrition.calories)) 千卡")
                        }
                        .chartXAxis {
                            AxisMarks(values: days.map(\.date)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) }
                        }
                        .chartYAxis { AxisMarks(position: .leading) }
                        .frame(height: 230)
                        .accessibilityLabel("最近七天每日摄入，单位千卡")
                        Text("均值只包含有记录的日期。当天记录尚未完成时，数值也会随记餐更新。")
                            .font(.caption).foregroundStyle(.secondary)
                        VStack(spacing: 0) {
                            ForEach(days.reversed()) { day in
                                HStack {
                                    Text(day.date.formatted(.dateTime.month().day().weekday()))
                                    Spacer()
                                    Text(day.count == 0 ? "未记录" : "\(Theme.number(day.nutrition.calories)) 千卡")
                                        .foregroundStyle(day.count == 0 ? .secondary : .primary)
                                        .monospacedDigit()
                                }
                                .font(.subheadline)
                                .padding(.vertical, 14)
                                if day.id != days.first?.id { Divider() }
                            }
                        }
                    }
                }
                .padding(24)
            }
            .background(Theme.background)
            .navigationTitle("趋势")
        }
    }
}

private struct TrendDay: Identifiable {
    let date: Date
    let nutrition: Nutrition
    let count: Int
    var id: Date { date }
}
