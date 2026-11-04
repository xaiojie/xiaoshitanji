import SwiftUI
import NutritionCore

struct TodayView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("dailyCalorieGoal") private var goal = 0.0
    @State private var selectedDate = Date.now
    @State private var lastActiveDate = Date.now
    @State private var sheet: TodaySheet?

    private var records: [MealRecord] { diary.document.records(on: selectedDate) }
    private var nutrition: Nutrition { diary.document.total(on: selectedDate) }
    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    dateNavigation
                    intakeSummary
                    if let error = diary.loadError {
                        ErrorNotice(message: error)
                        Button("重新读取", action: diary.reload).buttonStyle(.bordered)
                    } else {
                        mealList
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle(isToday ? "今天" : "饮食日记")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("选择日期", systemImage: "calendar") { sheet = .calendar }
                        .accessibilityIdentifier("chooseDate")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    sheet = .record(MealRecord.draft(on: selectedDate))
                } label: {
                    Label("记录饮食", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .disabled(diary.loadError != nil)
                .accessibilityIdentifier("addMeal")
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
            }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .record(let record):
                    ComposerView(record: record, isEditing: diary.document.records.contains { $0.id == record.id })
                case .calendar:
                    NavigationStack {
                        DatePicker("记录日期", selection: $selectedDate, in: ...Date.now, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .padding()
                            .navigationTitle("选择日期")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { sheet = nil } } }
                    }
                    .presentationDetents([.medium])
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshSelectedDay() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                refreshSelectedDay()
            }
        }
    }

    private var dateNavigation: some View {
        HStack {
            Text(selectedDate.formatted(.dateTime.month().day().weekday(.wide)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button("前一天", systemImage: "chevron.left") { moveDate(by: -1) }
                    Button("后一天", systemImage: "chevron.right") { moveDate(by: 1) }
                        .disabled(isToday)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.regular)
            }
        }
    }

    private var intakeSummary: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("已摄入").font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(Theme.number(nutrition.calories))
                    .font(.system(size: 64, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .accessibilityIdentifier("dailyCalories")
                Text("千卡").font(.title3).foregroundStyle(.secondary)
            }
            if goal > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("参考目标 \(Theme.number(goal)) · \(goalDescription)")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ProgressView(value: min(nutrition.calories, goal), total: goal)
                        .tint(Theme.sage)
                        .accessibilityLabel("参考目标进度")
                }
            } else {
                Text("已记录 \(records.count) 餐 · 热量单位为 kcal")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            NutritionRow(nutrition: nutrition).padding(.top, 4)
        }
        .animation(.snappy, value: nutrition.calories)
    }

    private var goalDescription: String {
        nutrition.calories <= goal
            ? "距目标 \(Theme.number(goal - nutrition.calories)) 千卡"
            : "较目标多 \(Theme.number(nutrition.calories - goal)) 千卡"
    }

    private var mealList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(isToday ? "今日" : "当日")饮食").font(.title2.bold())
                Spacer()
                if !records.isEmpty {
                    Text("\(records.count) 餐").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if records.isEmpty {
                ContentUnavailableView {
                    Label("从第一餐开始", systemImage: "fork.knife")
                } description: {
                    Text("用文字或照片记下吃了什么，\n也可以直接手动填写。")
                }
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(records) { record in
                        Button { sheet = .record(record) } label: { MealRow(record: record) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("meal-\(record.id)")
                        if record.id != records.last?.id { Divider().padding(.leading, 72) }
                    }
                }
                Text("AI 分析为估算值，点击记录可调整食物和份量。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func moveDate(by days: Int) {
        if let date = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
            selectedDate = date
        }
    }

    private func refreshSelectedDay() {
        if Calendar.current.isDate(selectedDate, inSameDayAs: lastActiveDate) {
            selectedDate = .now
        }
        lastActiveDate = .now
    }
}

private enum TodaySheet: Identifiable {
    case record(MealRecord)
    case calendar

    var id: String {
        switch self {
        case .record(let record): record.id.uuidString
        case .calendar: "calendar"
        }
    }
}

private struct MealRow: View {
    let record: MealRecord

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let data = record.photoJPEG, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: record.kind.symbol)
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.sage.opacity(0.12))
                }
            }
            .frame(width: 58, height: 62)
            .clipShape(.rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(record.kind.title).font(.headline)
                    Text(record.date, style: .time).font(.caption).foregroundStyle(.secondary)
                }
                Text(record.foodNames).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Theme.number(record.nutrition.calories)).font(.headline).monospacedDigit()
                Text("千卡").font(.caption).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 14)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
