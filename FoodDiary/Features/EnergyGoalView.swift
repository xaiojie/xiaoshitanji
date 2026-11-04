import SwiftUI
import NutritionCore

/// 能量目标：用 BMR × 活动系数估算维持热量，再按减脂/增肌推导每日目标与三大宏量。
struct EnergyGoalView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(\.dismiss) private var dismiss
    @State private var settings: EnergySettings
    @State private var birthYearText: String
    @State private var errorMessage: String?

    init(settings: EnergySettings?) {
        let value = settings ?? EnergySettings()
        _settings = State(initialValue: value)
        _birthYearText = State(initialValue: String(value.birthYear))
    }

    private var heightCM: Double? { diary.document.profile.heightCM }
    private var weightKG: Double? { diary.weightKG(on: .now) }

    private var draft: EnergySettings {
        var copy = settings
        if let year = Int(birthYearText) { copy.birthYear = year }
        return copy
    }

    private var budget: EnergyBudget? {
        guard let heightCM, let weightKG else { return nil }
        return try? EnergyCalculator.budget(settings: draft, weightKG: weightKG, heightCM: heightCM)
    }

    private var calibration: MaintenanceCalibration? { diary.calibrationSuggestion() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                identityCard
                goalCard
                if let budget { previewCard(budget) }
                calibrationCard
                if let errorMessage { ErrorNotice(message: errorMessage).contentCard() }
                Text("能量目标是估算值，不是医学建议。体重变化连续 2–4 周偏离预期时，用校准或调整每周速度修正。")
                    .font(.caption2).foregroundStyle(Theme.mutedInk).padding(.horizontal, 4)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .background(Theme.background)
        .navigationTitle("能量目标")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save).fontWeight(.semibold)
            }
        }
        .onChange(of: birthYearText) { _, value in
            let digits = value.filter(\.isNumber).prefix(4)
            if digits != value { birthYearText = String(digits) }
        }
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("基础信息").font(.headline)
            BrandSegments(options: BiologicalSex.allCases.map { ($0, $0.title) }, selection: $settings.sex)
            HStack {
                Text("出生年份").font(.subheadline)
                Spacer()
                TextField("1995", text: $birthYearText)
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    .frame(width: 90).monospacedDigit()
                    .accessibilityIdentifier("energyBirthYear")
            }
            if let budget { Text("按 \(budget.age) 岁估算").font(.caption2).foregroundStyle(Theme.mutedInk) }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("日常活动").font(.subheadline)
                Picker("日常活动", selection: $settings.activity) {
                    ForEach(ActivityLevel.allCases) { level in Text(level.title).tag(level) }
                }.pickerStyle(.menu).tint(Theme.ink)
                Text(settings.activity.detail).font(.caption).foregroundStyle(Theme.mutedInk)
            }
            if heightCM == nil || weightKG == nil {
                Text("先在「我的」里记录身高和体重，才能算出目标。")
                    .font(.caption).foregroundStyle(Theme.gold)
            } else {
                Text("身高 \(Theme.number(heightCM ?? 0)) 厘米 · 体重 \(Theme.number(weightKG ?? 0, decimals: 1)) 公斤")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
            }
        }
        .foregroundStyle(Theme.ink).contentCard()
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("目标").font(.headline)
            BrandSegments(options: GoalMode.allCases.map { ($0, $0.title) }, selection: $settings.goalMode)
            if settings.goalMode != .maintain {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("每周变化").font(.subheadline)
                        Spacer()
                        Text("\(Theme.number(settings.weeklyRate, decimals: 2)) 公斤")
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    Slider(value: $settings.weeklyRate, in: 0.1...1, step: 0.05).tint(Theme.gold)
                    Text("减脂建议每周 0.25–0.75 公斤；增肌按一半的热量盈余计算。")
                        .font(.caption2).foregroundStyle(Theme.mutedInk)
                }
            }
        }
        .foregroundStyle(Theme.ink).contentCard()
    }

    private func previewCard(_ budget: EnergyBudget) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("每日预算").font(.headline)
                Spacer()
                Text("\(Theme.number(budget.targetCalories)) 千卡")
                    .font(.system(.title3, design: .rounded, weight: .heavy)).monospacedDigit()
            }
            HStack(spacing: 12) {
                stat("基础代谢", budget.bmr)
                stat("维持", budget.maintenance)
                stat("已调整", budget.dailyDelta == 0 ? 0 : budget.dailyDelta)
            }
            Divider()
            HStack(spacing: 12) {
                macro("蛋白质", budget.proteinGrams, Theme.olive)
                macro("碳水", budget.carbGrams, Theme.carbohydrate)
                macro("脂肪", budget.fatGrams, Theme.fat)
            }
            Text(budget.usedCalibration ? "维持热量来自你的体重趋势校准。" : "维持热量来自公式估算，记录 2–4 周体重后可以校准。")
                .font(.caption2).foregroundStyle(Theme.mutedInk)
        }
        .foregroundStyle(Theme.ink).contentCard()
    }

    private var calibrationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("用体重校准").font(.headline)
            if settings.calibratedMaintenance != nil {
                Text("已采用校准值 \(Theme.number(settings.calibratedMaintenance ?? 0)) 千卡。")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
                Button("恢复公式估算") { settings.calibratedMaintenance = nil }
                    .font(.subheadline).buttonStyle(.bordered)
            } else if let calibration {
                Text("最近 \(Int(calibration.days.rounded())) 天平均摄入 \(Theme.number(calibration.averageIntake)) 千卡，体重变化 \(Theme.number(calibration.weightChangeKG, decimals: 1)) 公斤。")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
                Button("采用校准的维持热量 \(Theme.number(calibration.maintenance)) 千卡") {
                    settings.calibratedMaintenance = calibration.maintenance
                }
                .font(.subheadline.weight(.semibold)).buttonStyle(.borderedProminent).tint(Theme.ink)
            } else {
                Text("记录连续 2–4 周的体重与饮食后，可以反推真实维持热量。")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
            }
        }
        .foregroundStyle(Theme.ink).contentCard()
    }

    private func stat(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(Theme.mutedInk)
            Text("\(value >= 0 ? "" : "−")\(Theme.number(abs(value)))")
                .font(.system(.subheadline, design: .rounded, weight: .bold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func macro(_ title: String, _ grams: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(Theme.mutedInk)
            Text("\(Theme.number(grams)) 克").font(.system(.subheadline, design: .rounded, weight: .bold))
                .monospacedDigit().foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        do {
            try draft.validate()
            try diary.saveEnergySettings(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
