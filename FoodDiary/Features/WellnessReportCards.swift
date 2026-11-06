import SwiftUI
import NutritionCore

struct WellnessSnapshotCards: View {
    let snapshot: WellnessSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(snapshot.startDate.formatted(.dateTime.year().month().day())) — \(snapshot.endDate.formatted(.dateTime.year().month().day())) · \(snapshot.dayCount) 天")
                .font(.caption).foregroundStyle(Theme.mutedInk)
            BrandSection("饮食摄入", symbol: WellnessArea.diet.symbol) {
                row("已记录", value: "\(snapshot.diet.recordCount) 餐 · \(snapshot.diet.recordedDays) 天")
                row("记录日均摄入", value: number(snapshot.diet.average?.calories, unit: "千卡"))
                if let average = snapshot.diet.average { NutritionRow(nutrition: average) }
                Text("均值仅按有饮食记录的日期计算，未记完的日期也可能在内。")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
            }
            BrandSection("吸烟记录", symbol: WellnessArea.smoking.symbol) {
                row("自己抽的", value: snapshot.smoking.eventDays == 0 ? "暂无记录" : "\(snapshot.smoking.smoked) 根")
                row("分给别人", value: snapshot.smoking.eventDays == 0 ? "暂无记录" : "\(snapshot.smoking.shared) 根")
                row("包装标注累计", value: snapshot.smoking.smoked > snapshot.smoking.unknownNicotineCount ? "\(Theme.number(snapshot.smoking.knownNicotineMG, decimals: 2)) mg" : "暂无可用标注")
                if snapshot.smoking.unknownNicotineCount > 0 {
                    Text("\(snapshot.smoking.unknownNicotineCount) 根缺少尼古丁标注").font(.caption).foregroundStyle(Theme.mutedInk)
                }
                ForEach(snapshot.smoking.costs, id: \.currency) { cost in
                    row("个人折算费用 · \(cost.currency.title)", value: cost.amount.formatted(.currency(code: cost.currency.rawValue)))
                }
                if snapshot.smoking.unpricedCount > 0 {
                    Text("\(snapshot.smoking.unpricedCount) 根缺少价格").font(.caption).foregroundStyle(Theme.mutedInk)
                }
                Text("分烟和余量校准单独统计。无事件日期保留未知，尼古丁累计采用烟盒标注的烟气释放量。")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
            }
            BrandSection("身体测量", symbol: WellnessArea.body.symbol) {
                row("身高", value: number(snapshot.body.heightCM, unit: "厘米"))
                if snapshot.body.heightCM != nil {
                    Text("\(snapshot.body.heightSource == .appleHealth ? "Apple 健康" : "个人资料") · \(snapshot.body.heightDate.map { $0.formatted(.dateTime.year().month().day()) } ?? "未记录测量日期")")
                        .font(.caption).foregroundStyle(Theme.mutedInk)
                }
                row("最近体重", value: number(snapshot.body.latestWeight?.kilograms, unit: "公斤"))
                if let weight = snapshot.body.latestWeight {
                    Text("\(weight.source.title) · \(weight.date.formatted(.dateTime.year().month().day().hour().minute()))")
                        .font(.caption).foregroundStyle(Theme.mutedInk)
                }
                row("BMI", value: number(snapshot.body.bmi))
                row("目标体重", value: number(snapshot.body.targetWeightKG, unit: "公斤"))
                row("范围内体重变化", value: snapshot.body.weightChangeKG.map { "\($0 > 0 ? "+" : "")\(Theme.number($0, decimals: 2)) 公斤" } ?? "测量次数不足")
            }
            BrandSection("运动与活动", symbol: WellnessArea.activity.symbol) {
                if let training = snapshot.training, training.sessions > 0 {
                    row("本机训练", value: "\(training.sessions) 次 · \(training.minutes) 分钟")
                    row("其中跑步", value: "\(training.runningSessions) 次")
                    row("已记录跑步里程", value: number(training.runningDistanceMeters.map { $0 / 1000 }, unit: "公里"))
                    if let heartRate = training.averageSessionHeartRate {
                        row("训练平均心率的均值", value: number(heartRate, unit: "次/分"))
                        Text("来自 \(training.heartRateRecordedSessions) 次训练的已保存均值。")
                            .font(.caption).foregroundStyle(Theme.mutedInk)
                    }
                    Text("本机记录与下方 Apple 健康可能包含同一场训练，按来源分别展示。")
                        .font(.caption).foregroundStyle(Theme.mutedInk)
                }
                metric("步数", metric: snapshot.activity.steps, unit: "步")
                metric("活动能量", metric: snapshot.activity.activeCalories, unit: "千卡")
                metric("锻炼时长", metric: snapshot.activity.exerciseMinutes, unit: "分钟")
                metric("步行跑步距离", metric: snapshot.activity.distanceMeters, unit: "公里", divisor: 1000)
                Text(snapshot.includesHealth ? "每项分别显示可读取的累计值与覆盖天数。活动能量不含基础代谢，健康数据截至\(snapshot.endDate.formatted(.dateTime.month().day().hour().minute()))。" : "当前汇总未包含 Apple 健康活动数据。可打开健康开关后重新读取。")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
            }
        }
    }

    private func row(_ title: String, value: String) -> some View {
        LabeledContent(title) { Text(value).fontWeight(.semibold).multilineTextAlignment(.trailing) }
    }

    private func metric(_ title: String, metric: WellnessMetric, unit: String, divisor: Double = 1) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            row(title, value: number(metric.total.map { $0 / divisor }, unit: unit))
            Text("有数据 \(metric.observedDays) / \(snapshot.dayCount) 天").font(.caption2).foregroundStyle(Theme.mutedInk)
        }
    }

    private func number(_ value: Double?, unit: String = "") -> String {
        value.map { "\(Theme.number($0, decimals: 1))\(unit.isEmpty ? "" : " " + unit)" } ?? "暂无数据"
    }
}

struct WellnessReportCards: View {
    let report: WellnessReview
    @State private var expandedAreas: Set<WellnessArea> = []
    @State private var showingScope = false

    private var snapshot: WellnessSummary { report.snapshot }
    private var coverage: WellnessCoverage { snapshot.coverage }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            conclusion
            actions
            details
            scope
        }
    }

    /// 结论只有一个，数字放在 chip 里，覆盖度只出现一次。
    private var conclusion: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("综合观察", systemImage: "sparkles").font(.headline)
                Spacer()
                Text(snapshot.period.title).font(.caption).foregroundStyle(Theme.softYellow)
            }
            Text(report.summary).font(.body).lineSpacing(5).textSelection(.enabled)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                chip("覆盖 \(coverage.recordedDays)/\(coverage.windowDays) 天")
                if let average = snapshot.diet.average?.calories {
                    chip("日均 \(Theme.number(average)) 千卡")
                }
                if coverage.smokingDays > 0 {
                    chip("自抽 \(snapshot.smoking.smoked) 支 / \(coverage.smokingDays) 天")
                }
                if let steps = snapshot.activity.steps.average {
                    chip("日均 \(Theme.number(steps)) 步")
                }
            }
            Text("\(snapshot.startDate.formatted(.dateTime.year().month().day())) — \(snapshot.endDate.formatted(.dateTime.year().month().day())) · 生成于 \(report.generatedAt.formatted(.dateTime.month().day().hour().minute()))")
                .font(.caption2).foregroundStyle(Theme.surface.opacity(0.75))
        }
        .foregroundStyle(Theme.surface).padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.darkGradient, in: .rect(cornerRadius: 26))
    }

    private var actions: some View {
        BrandSection("今天能做这几件事", symbol: "checklist") {
            ForEach(Array(report.actions.enumerated()), id: \.offset) { index, action in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "\(index + 1).circle.fill").font(.title2).foregroundStyle(Theme.olive)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(action.title).font(.headline)
                        Text(action.detail).font(.subheadline).foregroundStyle(Theme.mutedInk).lineSpacing(4)
                    }
                }
            }
        }
    }

    /// 四类细节默认收起，先让人看到结论和行动。
    private var details: some View {
        BrandSection("四类细节", symbol: "list.bullet") {
            ForEach(report.observations) { observation in
                DisclosureGroup(isExpanded: expansion(for: observation.area)) {
                    Text(observation.text).font(.subheadline).lineSpacing(4)
                        .textSelection(.enabled).padding(.top, 8)
                } label: {
                    Label(observation.area.title, systemImage: observation.area.symbol).font(.subheadline.bold())
                }
                .tint(Theme.ink)
                .padding(.vertical, 4)
            }
            Text(missingSummary).font(.caption).foregroundStyle(Theme.mutedInk).lineSpacing(3)
        }
    }

    private var scope: some View {
        DisclosureGroup(isExpanded: $showingScope) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(snapshot.startDate.formatted(.dateTime.year().month().day())) — \(snapshot.endDate.formatted(.dateTime.year().month().day().hour().minute()))")
                Text("饮食 \(coverage.dietDays) 天 · 吸烟 \(coverage.smokingDays) 天 · 体重 \(coverage.weightDays) 天 · 活动 \(coverage.activityDays) 天（共 \(coverage.windowDays) 天）")
                if let goal = snapshot.calorieGoal {
                    Text("参考目标 \(Theme.number(goal)) 千卡（你自己设的）")
                } else if let estimated = snapshot.suggestedTarget {
                    Text("估算参考 \(Theme.number(estimated)) 千卡（按个人资料算的，不是你的设定）")
                }
                ForEach(Array(report.limitations.enumerated()), id: \.offset) { _, item in
                    Label(item, systemImage: "info.circle")
                }
                Text(snapshot.includesHealth ? "含当时可读取的 Apple 健康数据。" : "使用当时的本机记录。")
                Text("数据更新后可重新分析，本报告对应生成时的记录快照。")
                Text(report.model).font(.caption2)
            }.font(.caption).foregroundStyle(Theme.mutedInk).padding(.top, 12)
        } label: {
            Label("数据范围与缺口", systemImage: "calendar").font(.subheadline.bold())
        }
        .tint(Theme.ink).contentCard()
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ink)
            .lineLimit(1).minimumScaleFactor(0.75)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface.opacity(0.94), in: .capsule)
    }

    private func expansion(for area: WellnessArea) -> Binding<Bool> {
        Binding(get: { expandedAreas.contains(area) },
                set: { expanded in
                    if expanded { expandedAreas.insert(area) } else { expandedAreas.remove(area) }
                })
    }

    /// 缺口只写一行，不再让每段正文重复免责声明。
    private var missingSummary: String {
        var items: [String] = []
        if coverage.dietDays == 0 { items.append("饮食") }
        if coverage.smokingDays == 0 { items.append("吸烟") }
        if coverage.weightDays == 0 { items.append("体重") }
        if snapshot.activity.steps.observedDays == 0 { items.append("活动") }
        if snapshot.activity.sleepHours.observedDays == 0 { items.append("睡眠") }
        if snapshot.activity.restingHeartRate.observedDays == 0 { items.append("静息心率") }
        if snapshot.activity.heartRateVariability.observedDays == 0 { items.append("HRV") }
        if snapshot.activity.vo2Max.observedDays == 0 { items.append("最大摄氧量") }
        return items.isEmpty ? "这次各类数据都有记录。" : "这次没有：" + items.joined(separator: "、")
    }
}
