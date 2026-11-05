import SwiftUI
import WidgetKit

struct IntakeEntry: TimelineEntry {
    let date: Date
    let snapshot: DiaryWidgetSnapshot?
}

struct IntakeProvider: TimelineProvider {
    private func current() -> IntakeEntry {
        IntakeEntry(date: .now, snapshot: DiaryWidgetStore.load())
    }

    func placeholder(in context: Context) -> IntakeEntry {
        IntakeEntry(date: .now, snapshot: DiaryWidgetSnapshot(calories: 566, targetCalories: 1800,
            protein: 34, carbohydrate: 58, fat: 22, mealCount: 2,
            meals: [.init(kind: .breakfast, calories: 208, recordCount: 1),
                    .init(kind: .lunch, calories: 358, recordCount: 1),
                    .init(kind: .dinner, calories: 0, recordCount: 0),
                    .init(kind: .snack, calories: 0, recordCount: 0)]))
    }

    func getSnapshot(in context: Context, completion: @escaping (IntakeEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<IntakeEntry>) -> Void) {
        let now = Date.now
        let snapshot = DiaryWidgetStore.load()
        let current = snapshot.flatMap { $0.isCurrent(on: now) ? $0 : nil }
        let entries = [IntakeEntry(date: now, snapshot: current),
                       IntakeEntry(date: DiaryWidgetTimeline.nextMidnight(after: now), snapshot: nil)]
        completion(Timeline(entries: entries, policy: .after(DiaryWidgetTimeline.nextRefresh(after: now))))
    }

}

struct IntakeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: IntakeEntry

    var body: some View {
        IntakeWidgetContent(snapshot: entry.snapshot, date: entry.date, compact: family == .systemSmall)
            .widgetURL(DiaryWidgetRoute.today.url)
    }
}

struct IntakeWidget: Widget {
    let kind = "IntakeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: IntakeProvider()) { entry in
            IntakeWidgetView(entry: entry)
                .containerBackground(for: .widget) { IntakeWidgetPalette.background }
        }
        .configurationDisplayName("今日摄入")
        .description("今天吃了多少、还剩多少，一眼看到。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct FoodDiaryWidgetBundle: WidgetBundle {
    var body: some Widget {
        IntakeWidget()
        IntakeLiveActivityWidget()
    }
}
