import SwiftUI
import Charts
import NutritionCore

struct TrendsView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(\.scenePhase) private var scenePhase
    @State private var dayCount = 7
    @State private var currentDate = Date.now
    /// 每张图各自的拖动位置，互不串台。
    @State private var calorieProbe: Date?
    @State private var scoreProbe: Date?
    @State private var weightProbe: Date?
    @State private var workoutProbe: Date?
    @State private var smokeProbe: Date?

    private var days: [TrendDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: currentDate)
        let span: Int
        if dayCount == 0 {
            let dates = diary.document.records.map(\.date)
                + diary.document.weights.map(\.date)
                + diary.document.workouts.map(\.date)
                + diary.document.smoking.events.map(\.date)
            let earliest = dates.min() ?? today
            span = min(365, (calendar.dateComponents([.day], from: calendar.startOfDay(for: earliest), to: today).day ?? 0) + 1)
        } else {
            span = dayCount
        }
        return (-(max(span, 1) - 1)...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let weights = diary.document.weights.filter { calendar.isDate($0.date, inSameDayAs: date) }
            return TrendDay(date: date, nutrition: diary.document.total(on: date),
                            count: diary.document.records(on: date).count,
                            score: diary.document.review(on: date)?.score,
                            workoutMinutes: diary.document.workouts(on: date).reduce(0) { $0 + $1.durationMinutes },
                            smokeCount: diary.document.smoking.events
                                .filter { $0.kind == .smoked && calendar.isDate($0.date, inSameDayAs: date) }
                                .reduce(0) { $0 + $1.count },
                            weight: weights.max { $0.date < $1.date }?.kilograms)
        }
    }

    private var weightDays: [TrendDay] { days.filter { $0.weight != nil } }
    private var workoutDays: [TrendDay] { days.filter { $0.workoutMinutes > 0 } }
    private var smokeDays: [TrendDay] { days.filter { $0.smokeCount > 0 } }
    private var recordedDays: [TrendDay] { days.filter { $0.count > 0 } }
    private var scoredDays: [TrendDay] { days.filter { $0.score != nil } }
    private var average: Nutrition {
        guard !recordedDays.isEmpty else { return .zero }
        return recordedDays.reduce(Nutrition.zero) { $0 + $1.nutrition }.scaled(by: 1 / Double(recordedDays.count))
    }
    private var probedDay: TrendDay? { ChartProbe.nearest(to: calorieProbe, in: recordedDays, date: \.date) }

    private var probedScoreDay: TrendDay? { ChartProbe.nearest(to: scoreProbe, in: scoredDays, date: \.date) }
    private var probedWeightDay: TrendDay? { ChartProbe.nearest(to: weightProbe, in: weightDays, date: \.date) }
    private var probedWorkoutDay: TrendDay? { ChartProbe.nearest(to: workoutProbe, in: days, date: \.date) }
    private var probedSmokeDay: TrendDay? { ChartProbe.nearest(to: smokeProbe, in: days, date: \.date) }

    private func barColour(for day: TrendDay) -> Color {
        if let probedDay { return day.id == probedDay.id ? Theme.accent : Theme.gold.opacity(0.3) }
        return Calendar.current.isDate(day.date, inSameDayAs: currentDate) ? Theme.accent : Theme.gold.opacity(0.72)
    }

    private var dateRange: ClosedRange<Date> {
        let start = days.first?.date ?? currentDate
        let end = Calendar.current.date(byAdding: .day, value: 1, to: days.last?.date ?? currentDate) ?? currentDate
        return start...end
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    HStack {
                        BrandPageTitle(title: "趋势")
                        Spacer(minLength: 10)
                        BrandSegments(options: [(7, "7天"), (30, "30天"), (0, "全部")], selection: $dayCount).frame(width: 176)
                    }.padding(.horizontal, 3)
                    if let error = diary.loadError { ErrorNotice(message: error).contentCard() }
                    else {
                        calorieChart
                        if !weightDays.isEmpty { weightChart }
                        if !workoutDays.isEmpty { workoutChart }
                        if !smokeDays.isEmpty { smokeChart }
                        if !recordedDays.isEmpty { NutritionDistributionCard(nutrition: average) }
                        FrogCallout(text: recordedDays.isEmpty ? "先记一餐，趋势慢慢来。" : "这周有认真记，我看见了。",
                            detail: "最近\(dayCount)天，记录了\(recordedDays.count)天饮食。均值只按有记录的日期计算。")
                        if !scoredDays.isEmpty { scoreChart }
                        if !recordedDays.isEmpty { dayList }
                    }
                }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 18)
            }
            .background(Theme.background).toolbar(.hidden, for: .navigationBar)
            .onAppear { currentDate = .now }
            .onChange(of: dayCount) { _, _ in
                calorieProbe = nil; scoreProbe = nil; weightProbe = nil; workoutProbe = nil; smokeProbe = nil
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { currentDate = .now } }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in currentDate = .now }
        }
    }

    private var calorieChart: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("近\(dayCount)天日均摄入").font(.caption).foregroundStyle(.white.opacity(0.8))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(recordedDays.isEmpty ? "—" : Theme.number(average.calories))
                            .font(.system(size: 38, weight: .heavy, design: .rounded)).monospacedDigit()
                        Text("千卡").font(.caption)
                    }
                }
                Spacer(minLength: 4)
                Image("MilkFrogPeek").resizable().scaledToFit().frame(width: 78, height: 84).accessibilityHidden(true)
            }
            if recordedDays.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.bar.xaxis").font(.system(size: 30)).foregroundStyle(Theme.accent)
                    Text("从第一餐开始积累").font(.subheadline.bold())
                    Text("拍照或描述吃了什么，摄入趋势会在这里呈现。")
                        .font(.caption).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).frame(height: 150)
            } else {
                Chart {
                    ForEach(days) { day in
                        if day.count > 0 {
                            BarMark(x: .value("日期", day.date, unit: .day), y: .value("千卡", day.nutrition.calories))
                                .foregroundStyle(barColour(for: day))
                                .cornerRadius(4)
                                .accessibilityLabel(day.date.formatted(.dateTime.month().day()))
                                .accessibilityValue("\(Theme.number(day.nutrition.calories)) 千卡")
                        }
                    }
                    RuleMark(y: .value("记录日平均", average.calories))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4])).foregroundStyle(Theme.accent.opacity(0.35))
                    if let probedDay {
                        RuleMark(x: .value("选中", probedDay.date, unit: .day))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(.white.opacity(0.3))
                            .annotation(position: .top, spacing: 4,
                                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                ChartProbeBubble(title: ChartProbe.dayLabel(probedDay.date),
                                                 value: "\(Theme.number(probedDay.nutrition.calories)) 千卡",
                                                 detail: "\(probedDay.count) 餐 · 蛋白 \(Theme.number(probedDay.nutrition.protein)) g",
                                                 onDark: true)
                            }
                    }
                }
                .chartXSelection(value: $calorieProbe)
                .chartProbeFeedback(calorieProbe)
                .animation(.snappy(duration: 0.22), value: calorieProbe)
                .chartXScale(domain: dateRange)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: dayCount == 7 ? 1 : 5)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text("\(Calendar.current.component(.month, from: date))/\(Calendar.current.component(.day, from: date))")
                                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.75))
                            }
                        }
                    }
                }
                .chartYAxis(.hidden).frame(height: 165)
                .accessibilityLabel("最近\(dayCount)天饮食摄入，单位千卡")
            }
            Text(calorieProbe == nil
                 ? "按住图表左右拖动，看每一天的摄入。未记录日期保留空缺。"
                 : "当天未记完时数值仍会更新。")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
        }
        .foregroundStyle(Theme.surface).padding(20)
        .background(Theme.darkGradient, in: .rect(cornerRadius: 28))
    }

    private var scoreChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("AI 饮食搭配参考分", systemImage: "sparkles").font(.headline)
            Chart(scoredDays) { day in
                if let score = day.score {
                    PointMark(x: .value("日期", day.date, unit: .day), y: .value("评分", score))
                        .foregroundStyle(scoreProbe == nil ? Theme.olive
                                         : (day.id == probedScoreDay?.id ? Theme.olive : Theme.olive.opacity(0.32)))
                        .symbolSize(day.id == probedScoreDay?.id ? 90 : 55)
                        .accessibilityLabel(day.date.formatted(.dateTime.month().day())).accessibilityValue("\(score) 分")
                }
                if let probedScoreDay {
                    RuleMark(x: .value("选中", probedScoreDay.date, unit: .day))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Theme.olive.opacity(0.4))
                        .annotation(position: .top, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            ChartProbeBubble(title: ChartProbe.dayLabel(probedScoreDay.date),
                                             value: "\(probedScoreDay.score ?? 0) 分")
                        }
                }
            }
            .chartXSelection(value: $scoreProbe)
            .chartProbeFeedback(scoreProbe)
            .animation(.snappy(duration: 0.22), value: scoreProbe)
            .chartYScale(domain: 0...100).chartXScale(domain: dateRange)
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: dayCount == 7 ? 1 : 5)) { _ in AxisValueLabel(format: .dateTime.day()) } }
            .chartYAxis { AxisMarks(position: .leading, values: [0, 50, 100]) }.frame(height: 145)
            Text("评分来自当时生成的回顾，信息不足的日期保留空缺。")
                .font(.caption2).foregroundStyle(Theme.mutedInk)
        }.contentCard()
    }

    private var weightChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("体重").font(.headline)
                Spacer()
                Text("\(weightDays.count) 次称重").font(.caption).foregroundStyle(Theme.mutedInk)
            }
            Chart(weightDays) { day in
                if let weight = day.weight {
                    LineMark(x: .value("日期", day.date), y: .value("体重", weight))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("日期", day.date), y: .value("体重", weight))
                        .symbolSize(day.id == probedWeightDay?.id ? 90 : 35)
                }
                if let probedWeightDay, let weight = probedWeightDay.weight {
                    RuleMark(x: .value("选中", probedWeightDay.date))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Theme.olive.opacity(0.4))
                        .annotation(position: .top, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            ChartProbeBubble(title: ChartProbe.dayLabel(probedWeightDay.date),
                                             value: "\(Theme.number(weight, decimals: 2)) 公斤")
                        }
                }
            }
            .chartXSelection(value: $weightProbe)
            .chartProbeFeedback(weightProbe)
            .animation(.snappy(duration: 0.22), value: weightProbe)
            .chartYScale(domain: weightDomain)
            .frame(height: 160)
        }.contentCard()
    }

    private var weightDomain: ClosedRange<Double> {
        let values = weightDays.compactMap(\.weight)
        guard let low = values.min(), let high = values.max() else { return 40...100 }
        return (low - 1)...(high + 1)
    }

    private var workoutChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("训练时长").font(.headline)
                Spacer()
                Text("\(workoutDays.reduce(0) { $0 + $1.workoutMinutes }) 分钟").font(.caption).foregroundStyle(Theme.mutedInk)
            }
            Chart(days) { day in
                BarMark(x: .value("日期", day.date, unit: .day), y: .value("分钟", day.workoutMinutes))
                    .foregroundStyle(Theme.olive.gradient)
                    .opacity(workoutProbe == nil || day.id == probedWorkoutDay?.id ? 1 : 0.38)
                    .cornerRadius(4)
                if let probed = probedWorkoutDay {
                    RuleMark(x: .value("选中", probed.date, unit: .day))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Theme.olive.opacity(0.4))
                        .annotation(position: .top, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            ChartProbeBubble(title: ChartProbe.dayLabel(probed.date),
                                             value: "\(probed.workoutMinutes) 分钟")
                        }
                }
            }
            .chartXSelection(value: $workoutProbe)
            .chartProbeFeedback(workoutProbe)
            .animation(.snappy(duration: 0.22), value: workoutProbe)
            .chartXScale(domain: dateRange)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: dayCount == 7 ? 1 : 5)) {
                    AxisValueLabel(format: .dateTime.day())
                }
            }
            .frame(height: 140)
        }.contentCard()
    }

    private var smokeChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("抽烟").font(.headline)
                Spacer()
                Text("\(smokeDays.reduce(0) { $0 + $1.smokeCount }) 根").font(.caption).foregroundStyle(Theme.mutedInk)
            }
            Chart(days) { day in
                BarMark(x: .value("日期", day.date, unit: .day), y: .value("根数", day.smokeCount))
                    .foregroundStyle(Theme.gold.gradient)
                    .opacity(smokeProbe == nil || day.id == probedSmokeDay?.id ? 1 : 0.38)
                    .cornerRadius(4)
                if let probed = probedSmokeDay {
                    RuleMark(x: .value("选中", probed.date, unit: .day))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Theme.gold.opacity(0.5))
                        .annotation(position: .top, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            ChartProbeBubble(title: ChartProbe.dayLabel(probed.date),
                                             value: "\(probed.smokeCount) 根")
                        }
                }
            }
            .chartXSelection(value: $smokeProbe)
            .chartProbeFeedback(smokeProbe)
            .animation(.snappy(duration: 0.22), value: smokeProbe)
            .chartXScale(domain: dateRange)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: dayCount == 7 ? 1 : 5)) {
                    AxisValueLabel(format: .dateTime.day())
                }
            }
            .frame(height: 140)
        }.contentCard()
    }

    private var dayList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("每日记录").font(.headline)
                Spacer()
                Text("\(days.reduce(0) { $0 + $1.count }) 餐").font(.caption).foregroundStyle(Theme.mutedInk)
            }
            ForEach(days.reversed()) { day in
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(day.date.formatted(.dateTime.month().day().weekday())).font(.subheadline)
                        Text(day.count == 0 ? "未记录" : "已记录 \(day.count) 餐").font(.caption).foregroundStyle(Theme.mutedInk)
                    }
                    Spacer()
                    Text(day.count == 0 ? "—" : "\(Theme.number(day.nutrition.calories)) 千卡")
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                if day.id != days.first?.id { Divider() }
            }
        }.contentCard()
    }
}

private struct TrendDay: Identifiable {
    let date: Date
    let nutrition: Nutrition
    let count: Int
    let score: Int?
    let workoutMinutes: Int
    let smokeCount: Int
    let weight: Double?
    var id: Date { date }
}
