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
        IntakeEntry(date: .now, snapshot: DiaryWidgetSnapshot(calories: 1240, targetCalories: 1800,
                                                               protein: 82, carbohydrate: 140,
                                                               fat: 44, mealCount: 3))
    }

    func getSnapshot(in context: Context, completion: @escaping (IntakeEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<IntakeEntry>) -> Void) {
        let entry = current()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct IntakeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: IntakeEntry

    private let ink = Color(red: 0.18, green: 0.15, blue: 0.10)
    private let muted = Color(red: 0.48, green: 0.43, blue: 0.32)
    private let accent = Color(red: 1.00, green: 0.79, blue: 0.14)

    var body: some View {
        if let snapshot = entry.snapshot {
            content(snapshot)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "fork.knife").font(.title3)
                Text("打开小食痰记").font(.headline)
                Text("记一餐后这里会显示今日数字。").font(.caption).foregroundStyle(muted)
            }
            .foregroundStyle(ink)
        }
    }

    private func content(_ snapshot: DiaryWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(number(snapshot.calories)).font(.system(size: family == .systemSmall ? 30 : 34,
                                                            weight: .heavy, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text("千卡").font(.caption2.weight(.semibold))
                Spacer(minLength: 0)
                if family != .systemSmall {
                    Text(snapshot.mealCount == 0 ? "还没记" : "\(snapshot.mealCount) 餐")
                        .font(.caption2).foregroundStyle(muted)
                }
            }
            .foregroundStyle(ink)

            if let remaining = snapshot.remaining {
                Text(remaining >= 0 ? "还可摄入 \(number(remaining)) 千卡" : "超过 \(number(-remaining)) 千卡")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ink)
                GeometryReader { proxy in
                    let ratio = min(1, max(0, snapshot.calories / max(snapshot.targetCalories ?? 1, 1)))
                    ZStack(alignment: .leading) {
                        Capsule().fill(ink.opacity(0.12))
                        Capsule().fill(accent).frame(width: proxy.size.width * ratio)
                    }
                }
                .frame(height: 5)
            } else {
                Text("还没设置能量目标").font(.caption2).foregroundStyle(muted)
            }

            if family != .systemSmall {
                HStack(spacing: 10) {
                    nutrient("蛋白", snapshot.protein)
                    nutrient("碳水", snapshot.carbohydrate)
                    nutrient("脂肪", snapshot.fat)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func nutrient(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 9)).foregroundStyle(muted)
            Text("\(number(value))g").font(.caption2.weight(.semibold)).foregroundStyle(ink)
        }
    }

    private func number(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}

struct IntakeWidget: Widget {
    let kind = "IntakeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: IntakeProvider()) { entry in
            IntakeWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(red: 1.00, green: 0.87, blue: 0.29),
                                            Color(red: 1.00, green: 0.79, blue: 0.14)],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("今日摄入")
        .description("今天吃了多少、还剩多少，一眼看到。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct FoodDiaryWidgetBundle: WidgetBundle {
    var body: some Widget {
        IntakeWidget()
        IntakeLiveActivityWidget()
    }
}
