import SwiftUI
import Charts
import NutritionCore

enum ActivityMetric: String, CaseIterable, Identifiable {
    case steps, calories, minutes, distance, workouts
    case sleep, restingHeartRate, heartRate, hrv, vo2Max, audio
    var id: Self { self }
    var title: String {
        switch self {
        case .steps: "步数"
        case .calories: "活动消耗"
        case .minutes: "锻炼分钟"
        case .distance: "步行跑步距离"
        case .workouts: "体能训练"
        case .sleep: "睡眠"
        case .restingHeartRate: "静息心率"
        case .heartRate: "平均心率"
        case .hrv: "心率变异性"
        case .vo2Max: "有氧适能"
        case .audio: "耳机音量暴露"
        }
    }
    var symbol: String {
        switch self {
        case .steps: "shoeprints.fill"
        case .calories: "flame.fill"
        case .minutes: "figure.run"
        case .distance: "point.bottomleft.forward.to.point.topright.scurvepath"
        case .workouts: "dumbbell.fill"
        case .sleep: "bed.double.fill"
        case .restingHeartRate: "heart.fill"
        case .heartRate: "waveform.path.ecg"
        case .hrv: "waveform.path"
        case .vo2Max: "lungs.fill"
        case .audio: "headphones"
        }
    }
    var color: Color {
        switch self {
        case .steps: Theme.accent
        case .calories: .orange
        case .minutes: Theme.fat
        case .distance: .purple
        case .workouts: Theme.olive
        case .sleep: .indigo
        case .restingHeartRate: .red
        case .heartRate: .pink
        case .hrv: .teal
        case .vo2Max: .cyan
        case .audio: .yellow
        }
    }
    var artworkName: String {
        switch self {
        case .steps, .distance: "HealthShoe"
        case .calories: "HealthEnergy"
        case .minutes, .workouts: "HealthWorkout"
        case .sleep: "HealthSleep"
        case .restingHeartRate, .heartRate, .hrv, .vo2Max: "HealthHeart"
        case .audio: "HealthAudio"
        }
    }
    var unit: String {
        switch self {
        case .steps: "步"
        case .calories: "千卡"
        case .minutes: "分钟"
        case .distance: "公里"
        case .workouts: "分钟"
        case .sleep: "小时"
        case .restingHeartRate, .heartRate: "次/分"
        case .hrv: "毫秒"
        case .vo2Max: "毫升/公斤/分钟"
        case .audio: "分钟"
        }
    }
    var decimals: Int {
        switch self {
        case .distance: 2
        case .sleep, .vo2Max: 1
        default: 0
        }
    }
    var detail: String {
        switch self {
        case .steps: "来自 Apple 健康的每日累计步数。"
        case .calories: "来自 Apple 健康的活动能量，包含锻炼和日常活动中消耗的能量。"
        case .minutes: "来自 Apple 健康记录的锻炼分钟数。"
        case .distance: "来自 Apple 健康记录的步行与跑步距离。"
        case .workouts: "来自 Apple 健康的体能训练，按训练时长汇总。"
        case .sleep: "来自 Apple 健康（手表或睡眠 App）的睡着时长，按醒来那天统计。"
        case .restingHeartRate: "Apple 健康在静息状态下测得的心率。"
        case .heartRate: "当天所有心率样本的平均值。"
        case .hrv: "心率变异性（SDNN），数值越高通常代表恢复越好。"
        case .vo2Max: "有氧适能，Apple 健康估算的最大摄氧量。"
        case .audio: "戴耳机听音频的累计时长，用来观察用耳习惯。"
        }
    }
    func value(in day: HealthActivityDay) -> Double? {
        switch self {
        case .steps: day.steps
        case .calories: day.activeCalories
        case .minutes: day.exerciseMinutes
        case .distance: day.distanceMeters.map { $0 / 1000 }
        case .workouts: day.workoutMinutes
        case .sleep: day.sleepHours
        case .restingHeartRate: day.restingHeartRate
        case .heartRate: day.averageHeartRate
        case .hrv: day.heartRateVariabilityMS
        case .vo2Max: day.vo2Max
        case .audio: day.headphoneAudioMinutes
        }
    }
    func formatted(_ value: Double?) -> String {
        value.map { Theme.number($0, decimals: decimals) } ?? "—"
    }
}

struct ActivityChartCard: View {
    let metric: ActivityMetric
    let days: [HealthActivityDay]
    @State private var probe: Date?

    private var recorded: [HealthActivityDay] { days.filter { metric.value(in: $0) != nil } }
    private var probedDay: HealthActivityDay? { ChartProbe.nearest(to: probe, in: recorded, date: \.date) }
    private var dateRange: ClosedRange<Date> {
        let start = days.first?.date ?? Calendar.current.startOfDay(for: .now)
        let last = days.last?.date ?? start
        let end = Calendar.current.date(byAdding: .day, value: 1, to: last) ?? last
        return start...end
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                HStack(spacing: 9) {
                    ObjectIcon(metric.artworkName, size: 36)
                    Text(metric.title).font(.headline).foregroundStyle(Theme.ink)
                }
                Spacer()
                Text("近 7 天 · \(metric.unit)").font(.caption).foregroundStyle(.secondary)
            }
            if recorded.isEmpty {
                HealthEmptyView(symbol: metric.symbol, title: "暂无\(metric.title)数据", detail: "连接 Apple 健康并允许读取后，有记录的日期会显示在这里。", artwork: metric.artworkName)
            } else {
                Chart(days) { day in
                    if let value = metric.value(in: day) {
                        BarMark(x: .value("日期", day.date, unit: .day), y: .value(metric.unit, value))
                            .foregroundStyle(probe == nil || day.id == probedDay?.id
                                             ? metric.color.gradient
                                             : metric.color.opacity(0.28).gradient)
                            .cornerRadius(4)
                            .accessibilityLabel(day.date.formatted(.dateTime.month().day()))
                            .accessibilityValue("\(metric.formatted(value)) \(metric.unit)")
                    }
                    if let probedDay, let value = metric.value(in: probedDay) {
                        RuleMark(x: .value("选中", probedDay.date, unit: .day))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(metric.color.opacity(0.45))
                            .annotation(position: .top, spacing: 4,
                                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                ChartProbeBubble(title: ChartProbe.dayLabel(probedDay.date),
                                                 value: "\(metric.formatted(value)) \(metric.unit)",
                                                 detail: metric.title)
                            }
                    }
                }
                .chartXSelection(value: $probe)
                .chartProbeFeedback(probe)
                .animation(.snappy(duration: 0.22), value: probe)
                .chartXScale(domain: dateRange)
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 175)
                Text(probe == nil
                     ? "按住图表左右拖动看每天数值 · 有数据 \(recorded.count) 天"
                     : "有数据 \(recorded.count) 天 · 未读取到的日期保留空缺")
                    .font(.caption2).foregroundStyle(.secondary)
                    .animation(.easeInOut(duration: 0.15), value: probe == nil)
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
                if metric == .workouts {
                    HealthWorkoutListCard(workouts: health.workouts)
                }
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
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await health.refresh() }
    }
}

struct DietHealthDetailView: View {
    @Environment(DiaryModel.self) private var diary
    @State private var probe: Date?

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
                        Text("已记录 \(diary.document.records(on: .now).count) 餐 · 来自小食痰记")
                            .font(.caption).foregroundStyle(.secondary)
                    }.contentCard()
                    NutritionDistributionCard(nutrition: diary.document.total(on: .now))
                    VStack(alignment: .leading, spacing: 18) {
                        Text("近 7 天摄入").font(.headline)
                        Chart(dates, id: \.self) { date in
                            let probed = ChartProbe.nearest(to: probe, in: dates, date: { $0 })
                            let isSelected = probed.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
                            if !diary.document.records(on: date).isEmpty {
                                BarMark(x: .value("日期", date, unit: .day),
                                        y: .value("千卡", diary.document.total(on: date).calories))
                                    .foregroundStyle(probe == nil || isSelected ? Color.orange.gradient : Color.orange.opacity(0.28).gradient)
                                    .cornerRadius(4)
                            }
                            if let probed, let selected = dates.first(where: { Calendar.current.isDate($0, inSameDayAs: probed) }) {
                                RuleMark(x: .value("选中", selected, unit: .day))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    .foregroundStyle(Color.orange.opacity(0.45))
                                    .annotation(position: .top, spacing: 4,
                                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                        ChartProbeBubble(title: ChartProbe.dayLabel(selected),
                                                         value: "\(Theme.number(diary.document.total(on: selected).calories)) 千卡",
                                                         detail: "\(diary.document.records(on: selected).count) 餐")
                                    }
                            }
                        }
                        .chartXSelection(value: $probe)
                        .chartProbeFeedback(probe)
                        .animation(.snappy(duration: 0.22), value: probe)
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
        .toolbar(.visible, for: .navigationBar)
    }
}

struct HealthWorkoutListCard: View {
    let workouts: [HealthWorkout]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 9) {
                    ObjectIcon("HealthWorkout", size: 36)
                    Text("最近的体能训练").font(.headline).foregroundStyle(Theme.ink)
                }
                Spacer()
                Text("来自 Apple 健康").font(.caption).foregroundStyle(.secondary)
            }
            if workouts.isEmpty {
                HealthEmptyView(symbol: "dumbbell", title: "暂无训练记录", detail: "在 Apple 健康里记录一次训练后，这里会显示时长、消耗和心率。", artwork: "HealthWorkout")
            } else {
                ForEach(workouts.prefix(8)) { workout in
                    HStack(spacing: 12) {
                        ObjectIcon(workout.kind == .strength ? "HealthWorkout" : "HealthShoe", size: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(workout.title).font(.subheadline.weight(.medium))
                            Text(workout.date.formatted(.dateTime.month().day().hour().minute()))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(workout.summaryLine).font(.caption).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .contentCard()
    }
}

struct HealthEmptyView: View {
    let symbol: String
    let title: String
    let detail: String
    var artwork: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            if let artwork { ObjectIcon(artwork, size: 56) }
            else { Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(Theme.sage) }
            Text(title).font(.subheadline.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 20)
    }
}
