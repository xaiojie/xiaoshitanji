import SwiftUI
import NutritionCore

struct MealSectionCard: View {
    let kind: MealKind
    let records: [MealRecord]
    let onAdd: () -> Void
    let onRecord: (MealRecord) -> Void

    private var calories: Double { records.reduce(0) { $0 + $1.nutrition.calories } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                MealIcon(kind: kind)
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.title).font(.headline)
                    Text(records.isEmpty ? "记录这一餐的美味" : "\(Theme.number(calories)) 千卡 · \(records.count) 条记录")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button(action: onAdd) { Label(records.isEmpty ? "记录" : "添加", systemImage: "plus") }
                    .font(.caption.weight(.semibold)).buttonStyle(.bordered)
                    .accessibilityIdentifier("add-\(kind.rawValue)")
            }
            ForEach(records) { record in
                Divider()
                Button { onRecord(record) } label: {
                    HStack(spacing: 12) {
                        if let data = record.photoJPEG, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: 52, height: 56).clipShape(.rect(cornerRadius: 14))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.foodNames).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                            Text(record.foods.map(\.portionLabel).joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text(record.date, style: .time).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(Theme.number(record.nutrition.calories)).font(.subheadline.bold()).foregroundStyle(.primary)
                            Text("千卡").font(.caption2).foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain).accessibilityIdentifier("meal-\(record.id)")
            }
        }
        .contentCard()
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
            .buttonStyle(.glassProminent)
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
