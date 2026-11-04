import SwiftUI
import NutritionCore

struct MealSectionCard: View {
    @Environment(DiaryModel.self) private var diary
    let kind: MealKind
    let records: [MealRecord]
    let onAdd: () -> Void
    let onRecord: (MealRecord) -> Void
    @State private var expanded = false

    private var calories: Double { records.reduce(0) { $0 + $1.nutrition.calories } }
    private var thumbnail: String {
        switch kind {
        case .breakfast: "FoodBreakfast"
        case .lunch: "FoodLunch"
        case .snack: "FoodSnack"
        case .dinner: ""
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                if records.isEmpty { onAdd() }
                else { withAnimation(.snappy) { expanded.toggle() } }
            } label: {
                HStack(spacing: 11) {
                    mealImage
                    VStack(alignment: .leading, spacing: 5) {
                        Text(kind.title).font(.system(size: 16, weight: .bold))
                        if let first = records.first {
                            Text(records.count == 1 ? first.date.formatted(.dateTime.hour().minute()) : "\(records.count) 条饮食记录")
                                .font(.system(size: 11)).foregroundStyle(Theme.mutedInk)
                        } else {
                            Text("待记录").font(.system(size: 11)).foregroundStyle(Theme.mutedInk)
                        }
                    }
                    Spacer(minLength: 4)
                    if !records.isEmpty {
                        Text("\(Theme.number(calories)) 千卡").font(.system(size: 17, weight: .heavy)).monospacedDigit()
                    }
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0)).foregroundStyle(Theme.mutedInk)
                }
                .foregroundStyle(Theme.ink).frame(minHeight: 66).contentShape(.rect)
            }
            .buttonStyle(.plain).accessibilityIdentifier(records.isEmpty ? "add-\(kind.rawValue)" : "open-\(kind.rawValue)")
            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(records) { record in
                        Button { onRecord(record) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.foodNames).font(.subheadline.weight(.medium)).lineLimit(2)
                                    Text(record.foods.map(\.portionLabel).joined(separator: " · "))
                                        .font(.caption).foregroundStyle(Theme.mutedInk).lineLimit(2)
                                }
                                Spacer()
                                Text(record.date, style: .time).font(.caption).foregroundStyle(Theme.mutedInk)
                                Image(systemName: "pencil").font(.caption)
                            }.foregroundStyle(Theme.ink).padding(.vertical, 5)
                        }.buttonStyle(.plain).accessibilityIdentifier("meal-\(record.id)")
                    }
                    Button("再记一条\(kind.title)", systemImage: "plus", action: onAdd)
                        .font(.caption.weight(.semibold)).buttonStyle(.glass)
                }
                .padding(.leading, 65).padding(.bottom, 14)
            }
        }
    }

    @ViewBuilder private var mealImage: some View {
        if let record = records.first, let data = diary.photoData(for: record), let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: 54, height: 50)
                .clipShape(.rect(cornerRadius: 12)).accessibilityHidden(true)
        } else if !thumbnail.isEmpty {
            Image(thumbnail).resizable().scaledToFit().frame(width: 54, height: 56).accessibilityHidden(true)
        } else {
            Image(systemName: "takeoutbag.and.cup.and.straw.fill").font(.system(size: 30))
                .foregroundStyle(Theme.gold).frame(width: 54, height: 56).accessibilityHidden(true)
        }
    }
}

struct RecordEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (MealKind) -> Void

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Label("记饮食", systemImage: "fork.knife").font(.headline)
                Spacer()
                Button("关闭", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)
            }
            Button { onSelect(.suggested()) } label: {
                Label("拍照或文字 · AI 便捷记餐", systemImage: "sparkles")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 46)
            }
            .yellowAction()
            HStack(spacing: 12) {
                ForEach(MealKind.allCases) { kind in
                    Button { onSelect(kind) } label: {
                        VStack(spacing: 10) {
                            MealIcon(kind: kind, size: 48)
                            Text("记\(kind.title)").font(.caption.weight(.medium)).foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(24)
        .presentationBackground(Theme.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
