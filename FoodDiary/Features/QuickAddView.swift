import SwiftUI
import NutritionCore

/// 快速加食物：手填、常吃组合、搜索历史食物、复制最近吃过的一餐。
struct QuickAddView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(\.dismiss) private var dismiss
    let onFood: (FoodItem) -> Void
    let onTemplate: (MealTemplate) -> Void
    let onRecord: (MealRecord) -> Void
    @State private var query = ""
    @State private var manualEntry = false
    @State private var errorMessage: String?

    private var templates: [MealTemplate] { diary.document.recentTemplates(limit: 6) }
    private var foods: [FoodItem] { diary.document.matchingFoods(query: query, limit: query.isEmpty ? 6 : 10) }
    private var records: [MealRecord] { diary.document.recentRecords(limit: 6) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    manualCard
                    if !templates.isEmpty { templateCard }
                    if !foods.isEmpty || !query.isEmpty { foodCard }
                    if !records.isEmpty { recordCard }
                    if templates.isEmpty, foods.isEmpty, records.isEmpty {
                        Text("还没有历史记录。先手动填写一项食物，或让 AI 记一餐，之后就能在这里一键复用。")
                            .font(.subheadline).foregroundStyle(.secondary).contentCard()
                    }
                    if let errorMessage { ErrorNotice(message: errorMessage) }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("快速加食物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } }
            }
            .sheet(isPresented: $manualEntry) {
                ManualFoodView { food in
                    onFood(food)
                    dismiss()
                }
            }
        }
    }

    private var manualCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("手动填写营养", systemImage: "square.and.pencil").font(.headline)
            Text("知道热量或看过营养表时，不经过 AI 直接记。")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("手动填写一项食物", systemImage: "plus") { manualEntry = true }
                .font(.subheadline.weight(.medium)).yellowAction()
        }
        .contentCard()
    }

    private var templateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("常吃组合", systemImage: "star.fill").font(.headline)
            Text("保存过的整餐，一键套用到这一餐。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(templates) { template in
                Button {
                    diary.markTemplateUsed(id: template.id)
                    onTemplate(template)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "star.fill").foregroundStyle(Theme.gold)
                            .frame(width: 38, height: 38)
                            .background(Theme.softYellow, in: .circle)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text(template.foodSummary).font(.caption).foregroundStyle(Theme.mutedInk).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text("约 \(Theme.number(template.calories)) 千卡").font(.caption.weight(.medium))
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("删除这个组合", systemImage: "trash", role: .destructive) {
                        do { try diary.deleteTemplate(id: template.id) }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
                if template.id != templates.last?.id { Divider() }
            }
        }
        .contentCard()
    }

    private var foodCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("最近吃过的食物", systemImage: "magnifyingglass").font(.headline)
            TextField("搜索食物，例如：米饭", text: $query)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Theme.softYellow.opacity(0.4), in: .rect(cornerRadius: 14))
                .accessibilityIdentifier("quickAddSearch")
            if foods.isEmpty {
                Text("历史记录里没有找到「\(query)」。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(foods) { food in
                Button {
                    var copy = food
                    copy.id = UUID()
                    onFood(copy)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: food.nutritionLabel == nil ? "fork.knife" : "doc.text.viewfinder")
                            .foregroundStyle(Theme.olive)
                            .frame(width: 38, height: 38)
                            .background(Theme.softGreen, in: .circle)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(food.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text(food.portionLabel).font(.caption).foregroundStyle(Theme.mutedInk)
                        }
                        Spacer(minLength: 4)
                        Text("约 \(Theme.number(food.nutrition.calories)) 千卡").font(.caption.weight(.medium))
                        Image(systemName: "plus.circle.fill").font(.body).foregroundStyle(Theme.gold)
                    }
                    .contentShape(.rect)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                if food.id != foods.last?.id { Divider() }
            }
        }
        .contentCard()
    }

    private var recordCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("最近吃过的一餐", systemImage: "clock.arrow.circlepath").font(.headline)
            Text("直接复制整餐的食物，再按今天的情况微调。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(records) { record in
                Button {
                    onRecord(record)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        MealIcon(kind: record.kind, size: 38)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.foodNames).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                            Text("\(record.date.formatted(.dateTime.month().day().hour().minute())) · \(Theme.number(record.nutrition.calories)) 千卡")
                                .font(.caption).foregroundStyle(Theme.mutedInk)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "doc.on.doc").font(.caption).foregroundStyle(Theme.olive)
                    }
                    .contentShape(.rect)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                if record.id != records.last?.id { Divider() }
            }
        }
        .contentCard()
    }
}

extension MealTemplate {
    var foodSummary: String { foods.map(\.name).joined(separator: " · ") }
    var calories: Double { foods.reduce(0) { $0 + $1.nutrition.calories } }
}
