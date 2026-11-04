import SwiftUI
import NutritionCore

struct TodayView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("dailyCalorieGoal") private var goal = 0.0
    @State private var selectedDate = Date.now
    @State private var lastActiveDate = Date.now
    @State private var sheet: TodaySheet?
    @State private var reviewTask: Task<Void, Never>?
    @State private var reviewRequestID: UUID?
    @State private var reviewError: String?

    private var records: [MealRecord] { diary.document.records(on: selectedDate) }
    private var nutrition: Nutrition { diary.document.total(on: selectedDate) }
    private var referenceGoal: Double? { goal > 0 && goal.isFinite ? goal : nil }
    private var review: DietReview? {
        guard let review = diary.document.review(on: selectedDate), review.calorieGoal == referenceGoal else { return nil }
        return review
    }
    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }
    private var foodCount: Int { Set(records.flatMap(\.foods).map(\.name)).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    dateNavigation
                    if let error = diary.loadError {
                        ErrorNotice(message: error).contentCard()
                        Button("重新读取", action: diary.reload).buttonStyle(.bordered)
                    } else {
                        DailyIntakeCard(nutrition: nutrition, goal: goal, mealCount: records.count,
                                        foodCount: foodCount, onGoal: { sheet = .settings })
                        NutritionDistributionCard(nutrition: nutrition)
                        CoachCard(review: review, recordCount: records.count, busy: reviewRequestID != nil, onAction: coachAction)
                        if let reviewError {
                            VStack(alignment: .leading, spacing: 12) {
                                ErrorNotice(message: reviewError)
                                Button("打开 DeepSeek 设置", systemImage: "key") { sheet = .settings }
                                    .font(.subheadline).buttonStyle(.bordered)
                            }
                            .contentCard()
                        }
                        HStack {
                            Text("\(isToday ? "今日" : "当日")饮食").font(.title3.bold())
                            Spacer()
                            Text("早餐到加餐，都好好记录").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4).padding(.top, 8)
                        ForEach(MealKind.allCases) { kind in
                            MealSectionCard(kind: kind, records: records.filter { $0.kind == kind },
                                onAdd: { openMeal(kind) }, onRecord: { sheet = .record($0) })
                        }
                        Text("食物份量与营养由 AI 估算，支持用日常语言继续修正。")
                            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
            }
            .background(Theme.background)
            .navigationTitle("饮食")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("选择日期", systemImage: "calendar") { sheet = .calendar }
                        .accessibilityIdentifier("chooseDate")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { sheet = .entry } label: {
                    Label("AI 记饮食", systemImage: "sparkles")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .disabled(diary.loadError != nil)
                .accessibilityIdentifier("addMeal")
                .padding(.horizontal, 24).padding(.vertical, 10)
            }
            .sheet(item: $sheet, content: sheetContent)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshSelectedDay() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshSelectedDay() }
            .onChange(of: selectedDate) { _, _ in cancelReview(); reviewError = nil }
            .onChange(of: goal) { _, _ in cancelReview(); reviewError = nil }
            .onDisappear(perform: cancelReview)
        }
    }

    private var dateNavigation: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(isToday ? "今天，也好好吃饭" : "回看这一天").font(.subheadline.weight(.medium))
                Text(selectedDate.formatted(.dateTime.month().day().weekday(.wide)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button("前一天", systemImage: "chevron.left") { moveDate(by: -1) }
                    Button("后一天", systemImage: "chevron.right") { moveDate(by: 1) }.disabled(isToday)
                }
                .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)
            }
        }
        .padding(.horizontal, 4).padding(.bottom, 4)
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
            SettingsView(isPresented: true)
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
                let key = try KeychainStore.load()
                let value = try await DeepSeekClient().reviewDay(records: snapshot, date: date,
                                                                 calorieGoal: analyzedGoal, apiKey: key)
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

    private func openMeal(_ kind: MealKind) {
        var record = MealRecord.draft(on: selectedDate)
        record.kind = kind
        sheet = .record(record)
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
    case calendar, entry, settings

    var id: String {
        switch self {
        case .record(let record): record.id.uuidString
        case .review(let review): review.id.uuidString
        case .calendar: "calendar"
        case .entry: "entry"
        case .settings: "settings"
        }
    }
}
