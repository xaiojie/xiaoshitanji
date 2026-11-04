import SwiftUI
import NutritionCore

private enum ProfileSection: String, CaseIterable, Identifiable {
    case today = "今日概况", ability = "身体能力", all = "全部数据"
    var id: Self { self }
}

private enum ProfileSheet: String, Identifiable {
    case editor, settings, weight, wellness, observation, sync, keepGoing, workouts
    var id: Self { self }
}

struct ProfileView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(HealthDataModel.self) private var health
    @State private var section = ProfileSection.today
    @State private var sheet: ProfileSheet?

    private var profile: HealthProfile { diary.document.profile }
    private var latestWeight: WeightRecord? { WeightRecord.latest(in: diary.document.weights + health.weights) }
    private var height: Double? { profile.heightCM ?? health.heightCM }
    private var heightDate: Date? { profile.heightCM == nil ? health.heightDate : profile.heightUpdatedAt }
    private var bmi: Double? { HealthProfile(heightCM: height).bmi(weightKG: latestWeight?.kilograms) }
    private var mealCount: Int { diary.document.records(on: .now).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    profileHeader
                    wellnessEntry
                    workoutsEntry
                    observationEntry
                    keepGoingEntry
                    syncEntry
                    BrandSegments(options: ProfileSection.allCases.map { ($0, $0.rawValue) }, selection: $section)
                    if let error = diary.loadError { ErrorNotice(message: error).contentCard() }
                    switch section {
                    case .today: todayOverview
                    case .ability: bodyAbility
                    case .all: allData
                    }
                    healthConnection
                    Button { sheet = .settings } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "gearshape").font(.title2)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("通用设置").font(.headline)
                                Text("AI 配置与个人参考目标").font(.caption).foregroundStyle(Theme.mutedInk)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }.foregroundStyle(Theme.ink).contentCard()
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 18)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $sheet) { destination in
                switch destination {
                case .editor: ProfileEditorView(profile: profile, effectiveHeight: height, weight: latestWeight, healthHeightDate: health.heightDate)
                case .settings: GeneralSettingsView(isPresented: true)
                case .weight: WeightEditorView()
                case .wellness: WellnessReviewView()
                case .observation: ObservationView()
                case .keepGoing: KeepGoingView()
                case .workouts: WorkoutLogView()
                case .sync: CloudSyncView()
                }
            }
            .refreshable { await health.refresh() }
        }
    }

    private var wellnessEntry: some View {
        Button { sheet = .wellness } label: {
            HStack(spacing: 13) {
                Image("MilkFrogPeek").resizable().scaledToFit().frame(width: 55, height: 62).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Label("汇总分析", systemImage: "sparkles").font(.headline)
                    Text("饮食、吸烟、身体与运动，一起看看。")
                        .font(.caption).foregroundStyle(Theme.surface.opacity(0.8))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.accent)
            }
            .foregroundStyle(Theme.surface).padding(.horizontal, 17).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.darkGradient, in: .rect(cornerRadius: 24))
        }.buttonStyle(.plain).accessibilityIdentifier("wellnessReview")
    }

    private var syncEntry: some View {
        Button { sheet = .sync } label: {
            HStack(spacing: 13) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 34)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Label("云端同步", systemImage: "icloud.and.arrow.up").font(.headline)
                    Text("换手机不丢记录，数据在自己的服务器。").font(.caption).foregroundStyle(Theme.mutedInk)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }.foregroundStyle(Theme.ink).contentCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cloudSyncEntry")
    }

    private var workoutsEntry: some View {
        Button { sheet = .workouts } label: {
            HStack(spacing: 13) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 30)).foregroundStyle(Theme.accent).frame(width: 38)
                VStack(alignment: .leading, spacing: 5) {
                    Label("训练记录", systemImage: "dumbbell").font(.headline)
                    Text("力量记组数重量，有氧记距离心率。").font(.caption).foregroundStyle(Theme.mutedInk)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.mutedInk)
            }.foregroundStyle(Theme.ink).contentCard()
        }.buttonStyle(.plain).accessibilityIdentifier("workoutsEntry")
    }

    private var keepGoingEntry: some View {
        Button { sheet = .keepGoing } label: {
            HStack(spacing: 13) {
                Image(systemName: "flame.circle.fill").font(.system(size: 34)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Label("青蛙的坚持", systemImage: "flame").font(.headline)
                    Text("连续天数、累计餐数和里程碑。").font(.caption).foregroundStyle(Theme.mutedInk)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.mutedInk)
            }.foregroundStyle(Theme.ink).contentCard()
        }.buttonStyle(.plain).accessibilityIdentifier("keepGoingEntry")
    }

    private var observationEntry: some View {
        Button { sheet = .observation } label: {
            HStack(spacing: 13) {
                Image(systemName: "eye.circle.fill").font(.system(size: 34)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Label("蛙的观察", systemImage: "sparkle.magnifyingglass").font(.headline)
                    Text("找模式，也能追问记录里的细节。").font(.caption).foregroundStyle(Theme.mutedInk)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.mutedInk)
            }.foregroundStyle(Theme.ink).contentCard()
        }.buttonStyle(.plain).accessibilityIdentifier("observationInsight")
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                Button { sheet = .editor } label: {
                    HStack(spacing: 13) {
                        ProfileAvatar(data: profile.avatarJPEG, size: 68)
                            .overlay { Circle().strokeBorder(Theme.surface, lineWidth: 3) }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(profile.nickname.isEmpty ? "蛙的搭子" : profile.nickname)
                                .font(.system(size: 23, weight: .heavy)).lineLimit(2)
                            Label("编辑个人资料", systemImage: "pencil").font(.system(size: 10, weight: .medium))
                        }
                    }.foregroundStyle(Theme.ink)
                }.buttonStyle(.plain).accessibilityIdentifier("editProfile")
                Spacer(minLength: 0)
                Button("通用设置", systemImage: "gearshape") { sheet = .settings }
                    .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)
                    .accessibilityIdentifier("generalSettings")
            }
            HStack(alignment: .top, spacing: 8) {
                headerMetric("身高", value: height, unit: "厘米")
                headerMetric("体重", value: latestWeight?.kilograms, unit: "公斤")
                headerMetric("BMI", value: bmi, unit: "自动计算")
                headerMetric("目标", value: profile.targetWeightKG, unit: "公斤")
            }
            .padding(.horizontal, 13).padding(.vertical, 12)
            .background(Theme.surface.opacity(0.88), in: .rect(cornerRadius: 20))
        }
        .padding(18).background(Theme.yellowGradient, in: .rect(cornerRadius: 30))
    }

    private func headerMetric(_ title: String, value: Double?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.map { Theme.number($0, decimals: 1) } ?? "—")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var todayOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                ForEach(ActivityMetric.allCases) { metric in
                    NavigationLink { HealthMetricDetailView(metric: metric) } label: {
                        dataRow(metric.title, symbol: metric.symbol, color: metric == .calories ? .orange : Theme.olive,
                            value: metric.value(in: health.today).map { "\(metric.formatted($0)) \(metric.unit)" } ?? "暂无数据")
                    }
                    Divider().padding(.leading, 45)
                }
                NavigationLink { WeightHistoryView() } label: {
                    dataRow("最近体重", symbol: "scalemass.fill", color: Theme.olive,
                        value: latestWeight.map { "\(Theme.number($0.kilograms, decimals: 1)) 公斤" } ?? "待记录")
                }
                Divider().padding(.leading, 45)
                NavigationLink { DietHealthDetailView() } label: {
                    dataRow("饮食摄入", symbol: "fork.knife", color: Theme.gold,
                        value: diary.loadError == nil ? "\(Theme.number(diary.document.total(on: .now).calories)) 千卡" : "暂无数据")
                }
                Divider().padding(.leading, 45)
                NavigationLink { EnergyGoalView(settings: diary.document.energy) } label: {
                    dataRow("能量目标", symbol: "flame.fill", color: Theme.gold,
                        value: diary.energyBudget(on: .now).map { "目标 \(Theme.number($0.targetCalories)) 千卡" } ?? "待设置")
                }
            }
            .buttonStyle(.plain).padding(.horizontal, 15).padding(.vertical, 5)
            .background(Theme.surface, in: .rect(cornerRadius: 24))
            Button("记录体重", systemImage: "plus") { sheet = .weight }
                .buttonStyle(.glass).frame(maxWidth: .infinity)
            Text("活动与饮食按今日记录汇总，体重采用最近一次测量。")
                .font(.caption2).foregroundStyle(Theme.mutedInk).padding(.horizontal, 4)
        }
    }

    private var bodyAbility: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading("身体与活动", subtitle: "从真实记录里，看见变化")
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("身体测量", systemImage: "figure.stand").font(.headline)
                    Spacer()
                    Button("完善", systemImage: "pencil") { sheet = .editor }.font(.caption)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(bmi.map { Theme.number($0, decimals: 1) } ?? "—")
                        .font(.system(size: 42, weight: .bold, design: .rounded)).foregroundStyle(Theme.olive)
                    Text("BMI").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                }
                Text(bmi == nil ? "补充身高和体重，即可自动计算 BMI。" : "根据当前使用的身高和最近一次体重测量计算。")
                    .font(.caption).foregroundStyle(.secondary)
                if let weight = latestWeight {
                    Text("体重测于 \(weight.date.formatted(.dateTime.year().month().day())) · \(weight.source.title)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(height == nil ? "身高待补充" : (profile.heightCM == nil ? "身高来自 Apple 健康" : "身高来自个人资料"))
                    .font(.caption2).foregroundStyle(.secondary)
                if height != nil {
                    Text(heightDate.map { "身高记录于 " + $0.formatted(.dateTime.year().month().day()) } ?? "身高未记录日期")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                NavigationLink { WeightHistoryView() } label: { Label("查看体重变化", systemImage: "chart.xyaxis.line") }
                    .font(.subheadline)
            }.contentCard()
            ForEach([ActivityMetric.steps, .calories, .minutes, .distance]) { metric in
                NavigationLink { HealthMetricDetailView(metric: metric) } label: {
                    ActivityChartCard(metric: metric, days: health.days)
                }.buttonStyle(.plain)
            }
            ForEach([ActivityMetric.workouts, .sleep, .restingHeartRate, .heartRate, .hrv, .vo2Max, .audio]) { metric in
                NavigationLink { HealthMetricDetailView(metric: metric) } label: {
                    ActivityChartCard(metric: metric, days: health.days)
                }.buttonStyle(.plain)
            }
            HealthWorkoutListCard(workouts: health.workouts)
        }
    }

    private var allData: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading("我的全部数据", subtitle: "身体测量、活动和每日饮食")
            VStack(spacing: 0) {
                NavigationLink { WeightHistoryView() } label: {
                    dataRow("体重", symbol: "scalemass.fill", color: Theme.olive,
                        value: latestWeight.map { "\(Theme.number($0.kilograms, decimals: 1)) 公斤" } ?? "暂无数据")
                }
                Divider().padding(.leading, 48)
                Button { sheet = .editor } label: {
                    dataRow("身高", symbol: "ruler", color: Theme.fat,
                        value: height.map { "\(Theme.number($0, decimals: 1)) 厘米" } ?? "待完善")
                }
                Divider().padding(.leading, 48)
                Button { sheet = .editor } label: {
                    dataRow("BMI", symbol: "figure.stand", color: .purple,
                        value: bmi.map { Theme.number($0, decimals: 1) } ?? "待完善")
                }
                Divider().padding(.leading, 48)
                Button { sheet = .editor } label: {
                    dataRow("目标体重", symbol: "flag.fill", color: .orange,
                        value: profile.targetWeightKG.map { "\(Theme.number($0, decimals: 1)) 公斤" } ?? "待设置")
                }
            }.buttonStyle(.plain).contentCard()
            VStack(spacing: 0) {
                ForEach(ActivityMetric.allCases) { metric in
                    NavigationLink { HealthMetricDetailView(metric: metric) } label: {
                        dataRow(metric.title, symbol: metric.symbol, color: metric.color,
                            value: metric.value(in: health.today).map { "\(metric.formatted($0)) \(metric.unit)" } ?? "暂无数据")
                    }
                    if metric != ActivityMetric.allCases.last { Divider().padding(.leading, 48) }
                }
            }.buttonStyle(.plain).contentCard()
            NavigationLink { DietHealthDetailView() } label: {
                dataRow("饮食摄入", symbol: "fork.knife", color: .orange,
                    value: diary.loadError == nil ? "\(Theme.number(diary.document.total(on: .now).calories)) 千卡" : "暂无数据")
                    .contentCard()
            }.buttonStyle(.plain)
            Text("活动与饮食显示今日累计值，体重采用最近一次测量。点击项目查看来源、日期和详细记录。")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
    }

    private var healthConnection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill").font(.title2).foregroundStyle(.pink)
                    .frame(width: 42, height: 42).background(Theme.surface, in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Apple 健康").font(.headline)
                    Text(health.accessRequested ? (health.hasData ? "数据来源 · 活动、睡眠、心率、有氧适能与训练" : "已请求访问，等待可读取的数据") : "连接活动、睡眠、心率与体能训练")
                        .font(.caption).foregroundStyle(Theme.mutedInk)
                }
                Spacer(minLength: 0)
                if health.isLoading { ProgressView() }
                else { Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.olive) }
            }
            if let refreshed = health.lastRefresh {
                Text("最近刷新 \(refreshed.formatted(.dateTime.month().day().hour().minute()))")
                    .font(.caption2).foregroundStyle(Theme.mutedInk)
            }
            if let error = health.errorMessage { ErrorNotice(message: error) }
            Button(health.accessRequested ? "健康连接与数据设置" : "连接 Apple 健康") {
                if health.accessRequested { sheet = .settings }
                else { Task { await health.connect() } }
            }.font(.caption.weight(.semibold)).disabled(health.isLoading || !health.isAvailable)
        }
        .padding(16).background(Theme.softGreen, in: .rect(cornerRadius: 22))
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.title3.bold())
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 4)
    }

    private func dataRow(_ title: String, symbol: String, color: Color, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 32, height: 38)
            Text(title).font(.subheadline).foregroundStyle(.primary)
            Spacer(minLength: 4)
            Text(value).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink).monospacedDigit()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }.padding(.vertical, 9).frame(minHeight: 48)
    }
}
