import SwiftUI
import NutritionCore

private enum ProfileSection: String, CaseIterable, Identifiable {
    case today = "今日概况", ability = "身体能力", all = "全部数据"
    var id: Self { self }
}

private enum ProfileSheet: String, Identifiable {
    case editor, settings, weight
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
                    Picker("健康数据分区", selection: $section) {
                        ForEach(ProfileSection.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    if let error = diary.loadError { ErrorNotice(message: error).contentCard() }
                    switch section {
                    case .today: todayOverview
                    case .ability: bodyAbility
                    case .all: allData
                    }
                    healthConnection
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("我的")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("通用设置", systemImage: "gearshape") { sheet = .settings }
                        .accessibilityIdentifier("generalSettings")
                }
            }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .editor: ProfileEditorView(profile: profile, effectiveHeight: height, weight: latestWeight, healthHeightDate: health.heightDate)
                case .settings: GeneralSettingsView(isPresented: true)
                case .weight: WeightEditorView()
                }
            }
            .refreshable { await health.refresh() }
        }
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 22) {
            Button { sheet = .editor } label: {
                HStack(spacing: 16) {
                    ProfileAvatar(data: profile.avatarJPEG, size: 72)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(profile.nickname.isEmpty ? "我的健康档案" : profile.nickname)
                            .font(.title2.bold()).foregroundStyle(.primary).lineLimit(2)
                        Text(profile.nickname.isEmpty ? "完善资料，开始了解自己" : "每一天，记录自己的变化")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "pencil").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain).accessibilityLabel("编辑个人资料").accessibilityIdentifier("editProfile")
            Divider()
            HStack(alignment: .top, spacing: 10) {
                headerMetric("身高", value: height, unit: "厘米")
                headerMetric("体重", value: latestWeight?.kilograms, unit: "公斤")
                headerMetric("BMI", value: bmi, unit: "自动计算")
                headerMetric("目标", value: profile.targetWeightKG, unit: "公斤")
            }
        }
        .contentCard()
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
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("今天的健康足迹", subtitle: Date.now.formatted(.dateTime.month().day().weekday()))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                NavigationLink { WeightHistoryView() } label: {
                    HealthSummaryTile(title: "最近体重", symbol: "scalemass.fill", color: Theme.accent,
                        value: latestWeight.map { Theme.number($0.kilograms, decimals: 1) } ?? "—", unit: "公斤",
                        footnote: latestWeight.map { "\($0.date.formatted(.dateTime.month().day())) · \($0.source.title)" } ?? "记录一次真实测量")
                }
                NavigationLink { DietHealthDetailView() } label: {
                    HealthSummaryTile(title: "饮食摄入", symbol: "fork.knife", color: .orange,
                        value: diary.loadError == nil ? Theme.number(diary.document.total(on: .now).calories) : "—",
                        unit: "千卡", footnote: "今日已记录 \(mealCount) 餐")
                }
                ForEach(ActivityMetric.allCases) { metric in
                    NavigationLink { HealthMetricDetailView(metric: metric) } label: {
                        HealthSummaryTile(title: metric.title, symbol: metric.symbol, color: metric.color,
                            value: metric.formatted(metric.value(in: health.today)), unit: metric.unit,
                            footnote: metric.value(in: health.today) == nil ? "暂无可读取数据" : "今天 · Apple 健康")
                    }
                }
            }.buttonStyle(.plain)
            Button("记录体重", systemImage: "plus") { sheet = .weight }
                .buttonStyle(.glass).frame(maxWidth: .infinity)
            Text("活动消耗包含运动与日常活动。饮食摄入按食记中已保存的餐食汇总。")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
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
                        .font(.system(size: 42, weight: .bold, design: .rounded)).foregroundStyle(Theme.accent)
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
        }
    }

    private var allData: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading("我的全部数据", subtitle: "身体测量、活动和每日饮食")
            VStack(spacing: 0) {
                NavigationLink { WeightHistoryView() } label: {
                    dataRow("体重", symbol: "scalemass.fill", color: Theme.accent,
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill").font(.title3).foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Apple 健康").font(.headline)
                    Text(health.accessRequested ? (health.hasData ? "汇集你的身体与活动记录" : "已请求访问，等待可读取的数据") : "连接步数、活动和身体测量")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if health.isLoading { ProgressView() }
            }
            if let refreshed = health.lastRefresh {
                Text("最近刷新 \(refreshed.formatted(.dateTime.month().day().hour().minute()))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let error = health.errorMessage { ErrorNotice(message: error) }
            Button(health.accessRequested ? "健康连接与数据设置" : "连接 Apple 健康", systemImage: "arrow.up.right") {
                if health.accessRequested { sheet = .settings }
                else { Task { await health.connect() } }
            }
            .font(.subheadline.weight(.semibold)).disabled(health.isLoading || !health.isAvailable)
        }.contentCard()
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
            Text(value).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }.padding(.vertical, 9).frame(minHeight: 48)
    }
}

private struct HealthSummaryTile: View {
    let title: String
    let symbol: String
    let color: Color
    let value: String
    let unit: String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: symbol).foregroundStyle(color)
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(value).font(.system(size: 31, weight: .bold, design: .rounded))
                    .monospacedDigit().foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            Text(footnote).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(2).frame(minHeight: 28, alignment: .topLeading)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}
