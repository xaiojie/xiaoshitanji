import SwiftUI
import Charts
import NutritionCore

enum ActivityMetric: String, CaseIterable, Identifiable {
    case steps, calories, minutes, distance
    var id: Self { self }
    var title: String {
        switch self {
        case .steps: "步数"
        case .calories: "活动消耗"
        case .minutes: "锻炼时长"
        case .distance: "步行跑步距离"
        }
    }
    var symbol: String {
        switch self {
        case .steps: "shoeprints.fill"
        case .calories: "flame.fill"
        case .minutes: "figure.run"
        case .distance: "point.bottomleft.forward.to.point.topright.scurvepath"
        }
    }
    var color: Color {
        switch self {
        case .steps: Theme.accent
        case .calories: .orange
        case .minutes: Theme.fat
        case .distance: .purple
        }
    }
    var unit: String {
        switch self {
        case .steps: "步"
        case .calories: "千卡"
        case .minutes: "分钟"
        case .distance: "公里"
        }
    }
    var detail: String {
        switch self {
        case .steps: "来自 Apple 健康的每日累计步数。"
        case .calories: "来自 Apple 健康的活动能量，包含锻炼和日常活动中消耗的能量。"
        case .minutes: "来自 Apple 健康记录的锻炼分钟数。"
        case .distance: "来自 Apple 健康记录的步行与跑步距离。"
        }
    }
    func value(in day: HealthActivityDay) -> Double? {
        switch self {
        case .steps: day.steps
        case .calories: day.activeCalories
        case .minutes: day.exerciseMinutes
        case .distance: day.distanceMeters.map { $0 / 1000 }
        }
    }
    func formatted(_ value: Double?) -> String {
        value.map { Theme.number($0, decimals: self == .distance ? 2 : 0) } ?? "—"
    }
}

struct ActivityChartCard: View {
    let metric: ActivityMetric
    let days: [HealthActivityDay]

    private var recorded: [HealthActivityDay] { days.filter { metric.value(in: $0) != nil } }
    private var dateRange: ClosedRange<Date> {
        let start = days.first?.date ?? Calendar.current.startOfDay(for: .now)
        let last = days.last?.date ?? start
        let end = Calendar.current.date(byAdding: .day, value: 1, to: last) ?? last
        return start...end
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(metric.title, systemImage: metric.symbol).font(.headline).foregroundStyle(metric.color)
                Spacer()
                Text("近 7 天 · \(metric.unit)").font(.caption).foregroundStyle(.secondary)
            }
            if recorded.isEmpty {
                HealthEmptyView(symbol: metric.symbol, title: "暂无\(metric.title)数据", detail: "连接 Apple 健康并允许读取后，有记录的日期会显示在这里。")
            } else {
                Chart(days) { day in
                    if let value = metric.value(in: day) {
                        BarMark(x: .value("日期", day.date, unit: .day), y: .value(metric.unit, value))
                            .foregroundStyle(metric.color.gradient).cornerRadius(4)
                            .accessibilityLabel(day.date.formatted(.dateTime.month().day()))
                            .accessibilityValue("\(metric.formatted(value)) \(metric.unit)")
                    }
                }
                .chartXScale(domain: dateRange)
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 175)
                Text("有数据 \(recorded.count) 天 · 未读取到的日期保留空缺")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contentCard()
    }
}

struct HealthMetricDetailView: View {
    @Environment(HealthDataModel.self) private var health
    let metric: ActivityMetric

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("今天").font(.subheadline).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline) {
                        Text(metric.formatted(metric.value(in: health.today)))
                            .font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(metric.unit).foregroundStyle(.secondary)
                    }
                    Text(metric.detail).font(.caption).foregroundStyle(.secondary)
                    if let refreshed = health.lastRefresh {
                        Text("最近刷新 \(refreshed.formatted(.dateTime.month().day().hour().minute()))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }.contentCard()
                ActivityChartCard(metric: metric, days: health.days)
                VStack(alignment: .leading, spacing: 16) {
                    Text("每日数据").font(.headline)
                    ForEach(health.days.reversed()) { day in
                        HStack {
                            Text(day.date.formatted(.dateTime.month().day().weekday()))
                            Spacer()
                            Text(metric.value(in: day).map { "\(metric.formatted($0)) \(metric.unit)" } ?? "暂无数据")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }.font(.subheadline)
                    }
                    if health.days.isEmpty { Text("等待连接 Apple 健康").font(.subheadline).foregroundStyle(.secondary) }
                }.contentCard()
                if let error = health.errorMessage { ErrorNotice(message: error).contentCard() }
            }.padding(20)
        }
        .background(Theme.background).navigationTitle(metric.title).navigationBarTitleDisplayMode(.inline)
        .refreshable { await health.refresh() }
    }
}

struct DietHealthDetailView: View {
    @Environment(DiaryModel.self) private var diary

    private var dates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }
    private var dateRange: ClosedRange<Date> {
        let start = dates.first ?? Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: dates.last ?? start) ?? .now
        return start...end
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error = diary.loadError { ErrorNotice(message: error).contentCard() }
                else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("今日已记录摄入").font(.headline)
                        Text("\(Theme.number(diary.document.total(on: .now).calories)) 千卡")
                            .font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.orange)
                        Text("已记录 \(diary.document.records(on: .now).count) 餐 · 来自食记")
                            .font(.caption).foregroundStyle(.secondary)
                    }.contentCard()
                    NutritionDistributionCard(nutrition: diary.document.total(on: .now))
                    VStack(alignment: .leading, spacing: 18) {
                        Text("近 7 天摄入").font(.headline)
                        Chart(dates, id: \.self) { date in
                            if !diary.document.records(on: date).isEmpty {
                                BarMark(x: .value("日期", date, unit: .day),
                                        y: .value("千卡", diary.document.total(on: date).calories))
                                    .foregroundStyle(.orange.gradient).cornerRadius(4)
                            }
                        }
                        .chartXScale(domain: dateRange)
                        .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                        .frame(height: 180)
                        Text("仅汇总已保存的餐食，未记录日期保留空缺。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.contentCard()
                    VStack(spacing: 16) {
                        ForEach(dates.reversed(), id: \.self) { date in
                            HStack {
                                Text(date.formatted(.dateTime.month().day()))
                                Spacer()
                                Text(diary.document.records(on: date).isEmpty ? "未记录" : "\(Theme.number(diary.document.total(on: date).calories)) 千卡")
                                    .foregroundStyle(.secondary)
                            }.font(.subheadline)
                        }
                    }.contentCard()
                }
            }.padding(20)
        }
        .background(Theme.background).navigationTitle("饮食摄入").navigationBarTitleDisplayMode(.inline)
    }
}

struct HealthEmptyView: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(Theme.sage)
            Text(title).font(.subheadline.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 20)
    }
}
