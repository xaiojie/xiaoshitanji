import SwiftUI
import Charts
import NutritionCore

private enum SmokingSheet: Identifiable {
    case choosePack, share, stock, history, edit(CigarettePack)
    var id: String {
        switch self {
        case .choosePack: "choosePack"
        case .share: "share"
        case .stock: "stock"
        case .history: "history"
        case .edit(let pack): pack.id.uuidString
        }
    }
}

struct SmokingView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(\.scenePhase) private var scenePhase
    @State private var currentDate = Date.now
    @State private var sheet: SmokingSheet?
    @State private var errorMessage: String?
    @State private var feedback: String?

    private var journal: SmokingDiary { diary.document.smoking }
    private var today: SmokingDaySummary { journal.summary(on: currentDate) }
    private var pack: CigarettePack? { journal.activePack }
    private var remaining: Int { pack.map { journal.remaining(in: $0.id) } ?? 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        BrandPageTitle(title: "戒烟")
                        Spacer()
                        Button("全部记录与烟包", systemImage: "clock.arrow.circlepath") { sheet = .history }
                            .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)
                    }.padding(.horizontal, 3)
                    todayHero
                    currentPack
                    Button(action: recordOne) {
                        Label(pack == nil ? "选择当前烟包" : (remaining == 0 ? "换一包" : "记录一根"), systemImage: "wind")
                            .font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 46)
                    }.yellowAction().disabled(diary.loadError != nil).accessibilityIdentifier("smokeOne")
                    HStack(spacing: 12) {
                        Button { sheet = .share } label: {
                            Label("分给别人", systemImage: "person.2").frame(maxWidth: .infinity, minHeight: 30)
                        }.disabled(pack == nil || remaining == 0)
                        Button { sheet = .choosePack } label: {
                            Label("换一包", systemImage: "arrow.left.arrow.right").frame(maxWidth: .infinity, minHeight: 30)
                        }
                    }.font(.subheadline.weight(.semibold)).buttonStyle(.glass).controlSize(.large)
                    if let error = diary.loadError ?? errorMessage { ErrorNotice(message: error).contentCard() }
                    if let feedback { Text(feedback).font(.caption).foregroundStyle(Theme.mutedInk).padding(.horizontal, 4) }
                    personalSummary
                    SmokingTrendCard(journal: journal, endingOn: currentDate)
                    recentEvents
                    NicotineExplanation()
                }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 18)
            }
            .background(Theme.background).toolbar(.hidden, for: .navigationBar)
            .sheet(item: $sheet) { destination in
                switch destination {
                case .choosePack: SmokingPackPickerView()
                case .edit(let pack): SmokingPackEditorView(pack: pack)
                case .share: SmokingCountView(kind: .shared)
                case .stock: SmokingCountView(kind: .stockCheck)
                case .history: SmokingHistoryView()
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { currentDate = .now } }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in currentDate = .now }
            .onAppear { currentDate = .now }
        }
    }

    private var todayHero: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("今日已记录").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.82))
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(today.smoked)").font(.system(size: 78, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.accent).monospacedDigit().contentTransition(.numericText())
                        .accessibilityIdentifier("smokedToday")
                    Text("根").font(.title3.bold()).foregroundStyle(Theme.surface)
                }
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    if let last = journal.latestSmoke {
                        let minutes = max(0, Int(context.date.timeIntervalSince(last.date) / 60))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("距上次记录").font(.caption2)
                            Text(minutes < 60 ? "\(minutes) 分钟" : "\(minutes / 60) 小时 \(minutes % 60) 分钟")
                                .font(.caption.weight(.semibold))
                        }
                    } else { Text("从第一条记录开始").font(.caption) }
                }.foregroundStyle(.white.opacity(0.72))
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12)
            Image("MilkFrogStanding").resizable().scaledToFit().frame(width: 137, height: 211)
                .accessibilityHidden(true)
                .overlay(alignment: .topLeading) {
                    FrogSpeech(text: "下一根，\n晚点再说呗。")
                        .frame(width: 122).offset(x: -96, y: -6)
                }
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 5)
        .background(Theme.darkGradient, in: .rect(cornerRadius: 28))
        .animation(.snappy, value: today.smoked)
    }

    private var currentPack: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("当前烟包").font(.caption.weight(.semibold))
                Text(pack == nil ? "— / 20 根" : "\(remaining) / 20 根")
                    .font(.system(size: 21, weight: .heavy, design: .rounded)).monospacedDigit()
                Spacer(minLength: 0)
                if let pack {
                    Menu("烟包操作", systemImage: "ellipsis.circle") {
                        Button("校准余量", systemImage: "slider.horizontal.3") { sheet = .stock }
                        Button("AI 识别烟盒", systemImage: "viewfinder") { sheet = .edit(pack) }
                    }.labelStyle(.iconOnly).font(.body)
                }
            }
            HStack(spacing: 4) {
                ForEach(0..<20) { index in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(index < remaining ? Theme.gold : Theme.surface.opacity(0.65))
                        .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.surface, lineWidth: 1) }
                        .frame(maxWidth: .infinity).frame(height: 35)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pack == nil ? "尚未选择烟包" : "当前烟包剩余\(remaining)根，共20根")
            HStack {
                Text(pack?.product.name ?? "从已有香烟中选一包，或扫描新香烟")
                    .lineLimit(1)
                Spacer()
                Text("分给别人 \(today.shared) 根")
            }.font(.system(size: 10)).foregroundStyle(Theme.mutedInk)
        }
        .padding(16).background(Theme.yellowGradient.opacity(0.66), in: .rect(cornerRadius: 24))
    }

    private var personalSummary: some View {
        HStack(alignment: .top, spacing: 15) {
            VStack(alignment: .leading, spacing: 8) {
                Label("尼古丁标注累计", systemImage: "drop").font(.caption).foregroundStyle(Theme.mutedInk)
                Text(today.smoked == today.unknownNicotineCount ? "—" : "\(Theme.number(today.knownNicotineMG, decimals: 2)) mg")
                    .font(.title3.bold()).monospacedDigit()
                if today.unknownNicotineCount > 0 {
                    Text("\(today.unknownNicotineCount) 根缺少标注值").font(.caption2).foregroundStyle(Theme.mutedInk)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("自己抽的折算费用", systemImage: "creditcard").font(.caption).foregroundStyle(Theme.mutedInk)
                ForEach(SmokingCurrency.allCases) { currency in
                    if let cost = today.costs[currency] {
                        Text(cost, format: .currency(code: currency.rawValue)).font(.title3.bold())
                    }
                }
                if today.costs.isEmpty { Text("—").font(.title3.bold()) }
                if today.unpricedCount > 0 { Text("\(today.unpricedCount) 根缺少价格").font(.caption2).foregroundStyle(Theme.mutedInk) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.fixedSize(horizontal: false, vertical: true).contentCard()
    }

    private var recentEvents: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("最近记录").font(.headline)
                Spacer()
                Button("全部") { sheet = .history }.font(.caption)
            }
            ForEach(Array(journal.events.suffix(5).reversed())) { event in
                SmokingEventRow(event: event, productName: journal.packs.first { $0.id == event.packID }?.product.name ?? "")
            }
            if journal.events.isEmpty {
                Text("自己抽的、分出去的和余量校准都会留在这里。").font(.subheadline).foregroundStyle(Theme.mutedInk)
            } else if let last = journal.events.last {
                Button("撤销上一条 · \(last.kind.title) \(last.count) 根", systemImage: "arrow.uturn.backward") {
                    do { try diary.removeSmokingEvent(last.id); errorMessage = nil; feedback = "已撤销上一条记录。" }
                    catch { errorMessage = error.localizedDescription }
                }.font(.caption).foregroundStyle(Theme.mutedInk)
            }
        }.contentCard()
    }

    private func recordOne() {
        guard pack != nil, remaining > 0 else { sheet = .choosePack; return }
        currentDate = .now
        do { try diary.recordSmoking(.smoked, count: 1); errorMessage = nil; feedback = "已记录这一根，今天共记录 \(today.smoked) 根。" }
        catch { errorMessage = error.localizedDescription; feedback = nil }
    }
}

struct SmokingTrendCard: View {
    let journal: SmokingDiary
    let endingOn: Date
    private var dates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: endingOn)
        return (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("近 7 天记录").font(.headline); Spacer(); Text("根").font(.caption).foregroundStyle(.secondary) }
            Chart(dates, id: \.self) { date in
                let day = journal.summary(on: date)
                BarMark(x: .value("日期", date, unit: .day), y: .value("根数", day.smoked))
                    .foregroundStyle(by: .value("类型", "自己抽的"))
                    .position(by: .value("类型", "自己抽的"))
                BarMark(x: .value("日期", date, unit: .day), y: .value("根数", day.shared))
                    .foregroundStyle(by: .value("类型", "分给别人"))
                    .position(by: .value("类型", "分给别人"))
            }
            .chartForegroundStyleScale(["自己抽的": Theme.accent, "分给别人": Theme.fat])
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 180)
            Text("只汇总已记录的数量，余量校准单独保留在记录中。")
                .font(.caption2).foregroundStyle(.secondary)
        }.contentCard()
    }
}

struct SmokingEventRow: View {
    let event: SmokingEvent
    let productName: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.kind == .smoked ? "wind" : (event.kind == .shared ? "person.2" : "slider.horizontal.3"))
                .foregroundStyle(event.kind == .smoked ? Theme.olive : Theme.fat).frame(width: 30)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(event.kind.title) \(event.count) 根").font(.subheadline.weight(.medium))
                Text(productName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(event.date.formatted(.dateTime.month().day().hour().minute()))
                .font(.caption2).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}

struct NicotineExplanation: View {
    var body: some View {
        Label("尼古丁累计按烟盒上的每根标注值相加。该值通常是机器测定的烟气释放量，人体实际吸收会随抽吸方式变化。", systemImage: "info.circle")
            .font(.caption).foregroundStyle(.secondary).lineSpacing(3).padding(.horizontal, 4)
    }
}
