import SwiftUI
import NutritionCore

enum ProfileHealthCategory: String, CaseIterable, Identifiable {
    case body, activity, heart, recovery
    var id: Self { self }
    var title: String {
        switch self {
        case .body: "身体测量"
        case .activity: "活动与训练"
        case .heart: "心脏与体能"
        case .recovery: "睡眠与听力"
        }
    }
    var subtitle: String {
        switch self {
        case .body: "身高 · 体重 · BMI"
        case .activity: "步数 · 消耗 · 运动"
        case .heart: "心率 · HRV · 有氧适能"
        case .recovery: "睡眠 · 耳机使用"
        }
    }
    var artworkName: String {
        switch self {
        case .body: "HealthScale"
        case .activity: "HealthShoe"
        case .heart: "HealthHeart"
        case .recovery: "HealthSleep"
        }
    }
    var metrics: [ActivityMetric] {
        switch self {
        case .body: []
        case .activity: [.steps, .calories, .minutes, .distance, .workouts]
        case .heart: [.restingHeartRate, .heartRate, .hrv, .vo2Max]
        case .recovery: [.sleep, .audio]
        }
    }
}

struct ProfileHealthCategoryView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(HealthDataModel.self) private var health
    let category: ProfileHealthCategory

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    ObjectIcon(category.artworkName, size: 74)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(category.title).font(.title2.bold())
                        Text(category.subtitle).font(.subheadline).foregroundStyle(Theme.mutedInk)
                    }
                    Spacer(minLength: 0)
                }.padding(18).background(Theme.softYellow.opacity(0.65), in: .rect(cornerRadius: 26))
                if let error = diary.loadError { ErrorNotice(message: error).contentCard() }
                if category == .body {
                    ProfileBodyMeasurements()
                } else {
                    metricList
                    if let metric = category.metrics.first {
                        ActivityChartCard(metric: metric, days: health.days)
                    }
                    if category == .activity { HealthWorkoutListCard(workouts: health.workouts) }
                    Text("数值来自 Apple 健康，按今日可读取记录显示。点进每个指标，可查看日期、来源和每日变化。")
                        .font(.caption).foregroundStyle(Theme.mutedInk).lineSpacing(3)
                }
                if let error = health.errorMessage { ErrorNotice(message: error).contentCard() }
            }.padding(20)
        }
        .background(Theme.background)
        .navigationTitle(category.title).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await health.refresh() }
        .accessibilityIdentifier("healthCategory-\(category.rawValue)")
    }

    private var metricList: some View {
        VStack(spacing: 0) {
            ForEach(category.metrics) { metric in
                NavigationLink { HealthMetricDetailView(metric: metric) } label: {
                    HStack(spacing: 13) {
                        ObjectIcon(metric.artworkName, size: 46)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(metric.title).font(.subheadline.weight(.semibold))
                            Text(metric.value(in: health.today).map { "\(metric.formatted($0)) \(metric.unit)" } ?? "暂无数据")
                                .font(.subheadline).foregroundStyle(Theme.mutedInk).monospacedDigit()
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.mutedInk)
                    }.padding(.vertical, 12).contentShape(.rect)
                }.buttonStyle(.plain).accessibilityIdentifier("healthMetric-\(metric.rawValue)")
                if metric != category.metrics.last { Divider().padding(.leading, 59) }
            }
        }.padding(.horizontal, 16).background(Theme.surface, in: .rect(cornerRadius: 24))
    }
}

private enum BodyMeasurementSheet: String, Identifiable {
    case profile, weight
    var id: Self { self }
}

private struct ProfileBodyMeasurements: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(HealthDataModel.self) private var health
    @State private var sheet: BodyMeasurementSheet?
    private var profile: HealthProfile { diary.document.profile }
    private var weight: WeightRecord? { WeightRecord.latest(in: diary.document.weights + health.weights) }
    private var height: Double? { profile.heightCM ?? health.heightCM }
    private var heightDate: Date? { profile.heightCM == nil ? health.heightDate : profile.heightUpdatedAt }
    private var bmi: Double? { HealthProfile(heightCM: height).bmi(weightKG: weight?.kilograms) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 0) {
                NavigationLink { WeightHistoryView() } label: {
                    row("最近体重", value: weight.map { "\(Theme.number($0.kilograms, decimals: 1)) 公斤" } ?? "待记录")
                }
                Divider()
                Button { sheet = .profile } label: { row("身高", value: height.map { "\(Theme.number($0, decimals: 1)) 厘米" } ?? "待完善") }
                Divider()
                Button { sheet = .profile } label: { row("BMI", value: bmi.map { Theme.number($0, decimals: 1) } ?? "待完善") }
                Divider()
                Button { sheet = .profile } label: { row("目标体重", value: profile.targetWeightKG.map { "\(Theme.number($0, decimals: 1)) 公斤" } ?? "待设置") }
            }.buttonStyle(.plain).contentCard()
            Button { sheet = .weight } label: {
                HStack { ObjectIcon("HealthScale", size: 30); Text("记录体重").font(.headline) }
                    .frame(maxWidth: .infinity)
            }.yellowAction().accessibilityIdentifier("categoryAddWeight")
            VStack(alignment: .leading, spacing: 10) {
                Text("测量来源").font(.headline)
                Text(profile.heightCM == nil ? "身高来自 Apple 健康，或在个人资料中手动补充。" : "身高来自个人资料。")
                if let heightDate { Text("身高记录于 \(heightDate.formatted(.dateTime.year().month().day()))") }
                if let weight {
                    Text("体重测于 \(weight.date.formatted(.dateTime.year().month().day())) · \(weight.source.title)")
                }
                Text("BMI 根据当前身高和最近一次体重测量自动计算。")
            }.font(.caption).foregroundStyle(Theme.mutedInk).contentCard()
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .profile: ProfileEditorView(profile: profile, effectiveHeight: height, weight: weight, healthHeightDate: health.heightDate)
            case .weight: WeightEditorView()
            }
        }
    }

    private func row(_ title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.subheadline.weight(.medium))
            Spacer(minLength: 8)
            Text(value).font(.subheadline.bold()).monospacedDigit()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.mutedInk)
        }.foregroundStyle(Theme.ink).padding(.vertical, 15).contentShape(.rect)
    }
}
