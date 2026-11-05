import SwiftUI
import NutritionCore

struct TodayView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(HealthDataModel.self) private var health
    @Environment(WidgetNavigation.self) private var widgetNavigation
    @Environment(\.scenePhase) private var scenePhase
    @State private var aiConsent = AIConsent()
    @AppStorage("dailyCalorieGoal") private var goal = 0.0
    @State private var selectedDate = Date.now
    @State private var lastActiveDate = Date.now
    @State private var sheet: TodaySheet?
    @State private var reviewTask: Task<Void, Never>?
    @State private var reviewRequestID: UUID?
    @State private var reviewError: String?
    @State private var liveActivity = IntakeActivityManager.shared
    @State private var liveActivityError: String?

    private var records: [MealRecord] { diary.document.records(on: selectedDate) }
    private var nutrition: Nutrition { diary.document.total(on: selectedDate) }
    private var budget: EnergyBudget? { diary.energyBudget(on: selectedDate) }
    private var workoutTotals: HealthWorkoutTotals { health.workoutTotals(on: selectedDate) }
    /// 健康里录了训练就用健康的消耗，否则用手填的，避免同一场训练算两次。
    private var burned: Double {
        ActivityBurn.resolve(manual: diary.burnedCalories(on: selectedDate), health: workoutTotals.calories)
    }
    /// 目标 + 当天训练消耗；没有能量设置时退回旧的「参考热量」。
    private var balance: DailyBalance? { DailyBalance.make(budget: budget, burned: burned, intake: nutrition) }
    private var referenceGoal: Double? { balance?.target ?? (goal > 0 && goal.isFinite ? goal : nil) }
    private var reviewGoal: Double? { budget?.targetCalories ?? (goal > 0 && goal.isFinite ? goal : nil) }
    private var review: DietReview? {
        guard let review = diary.document.review(on: selectedDate), review.calorieGoal == reviewGoal else { return nil }
        return review
    }
    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }
    private var foodCount: Int { Set(records.flatMap(\.foods).map(\.name)).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let error = diary.loadError {
                        ErrorNotice(message: error).contentCard()
                        Button("重新读取", action: diary.reload).buttonStyle(.bordered)
                    } else {
                        DailyIntakeCard(nutrition: nutrition, goal: referenceGoal ?? 0, mealCount: records.count,
                            foodCount: foodCount, date: selectedDate, isToday: isToday,
                            goalNote: budget.map { note in
                                "\(Theme.number(note.maintenance)) 千卡维持 · \(Theme.number(note.proteinGrams)) 克蛋白"
                                    + (burned > 0 ? " · 训练 +\(Theme.number(burned))" : "")
                                    + (workoutTotals.hasWorkout ? " · 锻炼 \(workoutTotals.minutes) 分钟" : "")
                            },
                            onDate: { sheet = .calendar }, onPrevious: { moveDate(by: -1) }, onNext: { moveDate(by: 1) },
                            onGoal: { sheet = budget == nil ? .settings : .energy },
                            liveActivityRunning: liveActivity.isRunning,
                            onLiveActivity: toggleLiveActivity)
                        VStack(spacing: 0) {
                            ForEach([MealKind.breakfast, .lunch, .snack, .dinner]) { kind in
                                MealSectionCard(kind: kind, records: records.filter { $0.kind == kind },
                                    onAdd: { openMeal(kind) }, onRecord: { sheet = .record($0) })
                                if kind != .dinner { Divider().overlay(Theme.gold.opacity(0.07)).padding(.leading, 72) }
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Theme.surface, in: .rect(cornerRadius: 24))
                        CoachCard(review: review, recordCount: records.count, busy: reviewRequestID != nil, onAction: coachAction)
                        if let reviewError {
                            VStack(alignment: .leading, spacing: 12) {
                                ErrorNotice(message: reviewError)
                            }
                            .contentCard()
                        }
                        Text("食物份量与营养由 AI 估算，支持用日常语言继续修正。")
                            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                Button { sheet = .entry } label: {
                    Label("扫描记一餐", systemImage: "viewfinder")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent).tint(Theme.ink).foregroundStyle(Theme.surface)
                .disabled(diary.loadError != nil)
                .accessibilityIdentifier("addMeal")
                .padding(.horizontal, 24).padding(.vertical, 8)
                .background(Theme.background.opacity(0.95))
            }
            .sheet(item: $sheet, onDismiss: finishSheetNavigation, content: sheetContent)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    refreshSelectedDay()
                    consumePendingNavigation()
                }
            }
            .onAppear(perform: consumePendingNavigation)
            .onChange(of: widgetNavigation.pendingRoute) { _, _ in consumeWidgetRoute() }
            .onChange(of: diary.loadError) { _, error in
                if error == nil { consumePendingNavigation() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshSelectedDay() }
            .onChange(of: selectedDate) { _, _ in cancelReview(); reviewError = nil }
            .onChange(of: goal) { _, _ in cancelReview(); reviewError = nil }
            .onDisappear(perform: cancelReview)
            .alert("实时活动", isPresented: Binding(get: { liveActivityError != nil },
                                                   set: { if !$0 { liveActivityError = nil } })) {
                Button("好", role: .cancel) { liveActivityError = nil }
            } message: { Text(liveActivityError ?? "") }
        }
        .aiDataConsent(aiConsent)
    }

    @ViewBuilder
    private func sheetContent(_ destination: TodaySheet) -> some View {
        switch destination {
        case .record(let record):
            ComposerView(record: record, isEditing: diary.document.records.contains { $0.id == record.id })
                .presentationDetents([.large])
        case .entry:
            RecordEntrySheet(onSelect: openMeal)
        case .settings:
            GeneralSettingsView(isPresented: true)
        case .energy:
            NavigationStack { EnergyGoalView(settings: diary.document.energy) }
                .presentationDetents([.large])
        case .review(let value):
            DietReviewView(review: value, onRefresh: analyzeDay)
        case .calendar:
            NavigationStack {
                DatePicker("记录日期", selection: $selectedDate, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.graphical).padding()
                    .navigationTitle("选择日期").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { sheet = nil } } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func coachAction() {
        if let review { sheet = .review(review) }
        else if records.isEmpty { sheet = .entry }
        else { analyzeDay() }
    }

    private func analyzeDay() {
        guard reviewRequestID == nil else { return }
        let snapshot = records
        let date = selectedDate
        let analyzedGoal = referenceGoal
        let id = UUID()
        reviewRequestID = id
        reviewError = nil
        reviewTask = Task { @MainActor in
            defer { if reviewRequestID == id { reviewRequestID = nil } }
            do {
                try await aiConsent.requirePermission()
                let value = try await DeepSeekClient().reviewDay(records: snapshot, date: date,
                                                                 calorieGoal: analyzedGoal)
                try Task.checkCancellation()
                guard reviewRequestID == id, referenceGoal == analyzedGoal else { return }
                try diary.saveReview(value, snapshot: snapshot)
                if Calendar.current.isDate(selectedDate, inSameDayAs: date), sheet == nil { sheet = .review(value) }
            } catch is CancellationError {
                // A changed date cancels the presentation and keeps that day's records intact.
            } catch {
                if reviewRequestID == id { reviewError = error.localizedDescription }
            }
        }
    }

    private func cancelReview() {
        reviewRequestID = nil
        reviewTask?.cancel()
    }

    private func toggleLiveActivity() {
        if liveActivity.isRunning {
            liveActivity.end()
            return
        }
        liveActivity.start(state: IntakeActivityManager.state(for: diary.document, budget: budget))
        liveActivityError = liveActivity.errorMessage
    }

    /// 快捷指令留下的那句话：取一次就清掉，直接开记录页。
    private func consumePendingMeal() {
        guard sheet == nil, diary.loadError == nil, let text = PendingMeal.take() else { return }
        sheet = .record(PendingMeal.draft(from: text, now: selectedDate))
    }

    private func consumePendingNavigation() {
        consumePendingMeal()
        consumeWidgetRoute()
    }

    private func finishSheetNavigation() {
        widgetNavigation.mealPresentationEnded()
        consumePendingNavigation()
    }

    /// 组件“记一餐”直接打开编辑器，不经过餐次选择页，也不覆盖已有草稿。
    private func consumeWidgetRoute() {
        guard let request = widgetNavigation.takeRequest(canPresent: sheet == nil && diary.loadError == nil) else { return }
        cancelReview()
        lastActiveDate = .now
        if let draft = request.mealDraft() {
            selectedDate = draft.date
            sheet = .record(draft)
        } else {
            selectedDate = .now
        }
    }

    private func openMeal(_ kind: MealKind) {
        sheet = .record(MealRecord.draft(on: selectedDate, kind: kind))
    }

    private func moveDate(by days: Int) {
        if let date = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) { selectedDate = date }
    }

    private func refreshSelectedDay() {
        if Calendar.current.isDate(selectedDate, inSameDayAs: lastActiveDate) { selectedDate = .now }
        lastActiveDate = .now
    }
}

private enum TodaySheet: Identifiable {
    case record(MealRecord)
    case review(DietReview)
    case calendar, entry, settings, energy

    var id: String {
        switch self {
        case .record(let record): record.id.uuidString
        case .review(let review): review.id.uuidString
        case .calendar: "calendar"
        case .entry: "entry"
        case .settings: "settings"
        case .energy: "energy"
        }
    }
}
