import SwiftUI
import NutritionCore

private struct SmokingPackEdit: Identifiable {
    let id = UUID()
    let pack: CigarettePack
}

struct SmokingHistoryView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(\.dismiss) private var dismiss
    @State private var section = 0
    @State private var date = Date.now
    @State private var editing: SmokingPackEdit?
    @State private var deleting: SmokingEvent?
    @State private var errorMessage: String?
    private var journal: SmokingDiary { diary.document.smoking }
    private var events: [SmokingEvent] { journal.events.reversed().filter { Calendar.current.isDate($0.date, inSameDayAs: date) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    BrandSegments(options: [(0, "每日记录"), (1, "我的烟包")], selection: $section)
                    if section == 0 { dailyEvents }
                    else { packList }
                    if let errorMessage { ErrorNotice(message: errorMessage).contentCard() }
                    NicotineExplanation()
                }.padding(20)
            }
            .background(Theme.background).navigationTitle("全部戒烟数据").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(item: $editing) { SmokingPackEditorView(pack: $0.pack) }
            .alert("撤销这条记录？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { event in
                Button("撤销记录", role: .destructive) {
                    do { try diary.removeSmokingEvent(event.id); errorMessage = nil }
                    catch { errorMessage = error.localizedDescription }
                    self.deleting = nil
                }
                Button("保留", role: .cancel) { deleting = nil }
            }
        }
    }

    private var dailyEvents: some View {
        VStack(alignment: .leading, spacing: 18) {
            DatePicker("查看日期", selection: $date, in: ...Date.now, displayedComponents: .date).contentCard()
            let summary = journal.summary(on: date)
            HStack {
                Label("自己抽了 \(summary.smoked) 根", systemImage: "wind")
                Spacer()
                Text("分给别人 \(summary.shared) 根").foregroundStyle(.secondary)
            }.font(.subheadline).contentCard()
            ForEach(events) { event in
                HStack {
                    SmokingEventRow(event: event, productName: journal.packs.first { $0.id == event.packID }?.product.name ?? "")
                    Menu("管理这条记录", systemImage: "ellipsis") {
                        Button("撤销记录", systemImage: "arrow.uturn.backward", role: .destructive) { deleting = event }
                    }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }.contentCard()
            }
            if events.isEmpty {
                HealthEmptyView(symbol: "calendar", title: "当天暂无记录", detail: "记录会按你点击时的日期和时间保存。")
                    .contentCard()
            }
        }
    }

    private var packList: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(journal.packs.reversed()) { pack in
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(pack.product.name).font(.headline)
                            Text("\(pack.openedAt.formatted(.dateTime.year().month().day())) · 初始 \(pack.openingCount) 根")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("余 \(journal.remaining(in: pack.id)) 根").font(.subheadline.weight(.semibold))
                    }
                    HStack {
                        if pack.id == journal.activePackID {
                            Label("正在使用", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Theme.olive)
                        } else {
                            Button("切换到这包") {
                                do { try diary.activateSmokingPack(pack.id); errorMessage = nil }
                                catch { errorMessage = error.localizedDescription }
                            }.font(.caption)
                        }
                        Spacer()
                        Button("AI 识别", systemImage: "viewfinder") { editing = SmokingPackEdit(pack: pack) }.font(.caption)
                    }
                }.contentCard()
            }
            if journal.packs.isEmpty {
                HealthEmptyView(symbol: "rectangle.stack", title: "还没有烟包", detail: "回到戒烟页添加当前烟包，就能开始记录。")
                    .contentCard()
            }
        }
    }
}

struct SmokingCountView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(\.dismiss) private var dismiss
    let kind: SmokingEventKind
    @State private var count = 1
    @State private var errorMessage: String?

    private var pack: CigarettePack? { diary.document.smoking.activePack }
    private var remaining: Int { pack.map { diary.document.smoking.remaining(in: $0.id) } ?? 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FrogCallout(text: kind == .stockCheck ? "数一数，心里有数。" : "分出去的，单独记。",
                        detail: kind == .stockCheck ? "按手中实际余量校准库存。" : "数量会从当前烟包扣除，分烟单独统计。")
                    BrandSection("当前烟包", symbol: "rectangle.stack.fill") {
                        Text(pack?.product.name ?? "尚未添加").font(.title3.bold())
                        LabeledContent("记录余量", value: "\(remaining) 根")
                        Divider()
                        Stepper(value: $count, in: kind == .stockCheck ? 0...20 : 1...max(1, remaining)) {
                            LabeledContent(kind == .stockCheck ? "实际还剩" : "分给别人", value: "\(count) 根")
                        }.tint(Theme.gold)
                        Text(kind == .stockCheck ? "校准会保留已有抽烟和分烟历史。" : "本次分烟单独统计，个人摄入按自己抽的记录计算。")
                            .font(.caption).foregroundStyle(Theme.mutedInk)
                    }
                    if let errorMessage { ErrorNotice(message: errorMessage).contentCard() }
                }.padding(20)
            }
            .background(Theme.background)
            .navigationTitle(kind == .stockCheck ? "校准烟包余量" : "分给别人").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do { try diary.recordSmoking(kind, count: count); dismiss() }
                        catch { errorMessage = error.localizedDescription }
                    }.disabled(pack == nil || diary.loadError != nil || (kind == .shared && count > remaining))
                }
            }
            .onAppear { if kind == .stockCheck { count = remaining } }
        }
    }
}
