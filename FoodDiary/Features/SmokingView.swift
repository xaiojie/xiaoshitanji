import SwiftUI
import Charts
import NutritionCore

private enum SmokingSheet: Identifiable {
    case newPack, share, stock, history, edit(CigarettePack)
    var id: String {
        switch self {
        case .newPack: "new"
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
                VStack(alignment: .leading, spacing: 20) {
                    Text("给每一次选择，留一点觉察")
                        .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 4)
                    todayHero
                    if let error = diary.loadError ?? errorMessage { ErrorNotice(message: error).contentCard() }
                    if let feedback { Text(feedback).font(.caption).foregroundStyle(Theme.accent).padding(.horizontal, 4) }
                    personalSummary
                    currentPack
                    SmokingTrendCard(journal: journal, endingOn: currentDate)
                    recentEvents
                    NicotineExplanation()
                }.padding(20)
            }
            .background(Theme.background).navigationTitle("戒烟记录")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("全部记录与烟包", systemImage: "clock.arrow.circlepath") { sheet = .history }
                }
            }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .newPack: SmokingPackEditorView()
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
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Label("今天已记录", systemImage: "leaf").font(.subheadline.weight(.medium))
                Spacer()
                Text(currentDate.formatted(.dateTime.month().day().weekday())).font(.caption)
            }.foregroundStyle(.white.opacity(0.8))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(today.smoked)")
                    .font(.system(size: 80, weight: .light, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText()).accessibilityIdentifier("smokedToday")
                Text("根").font(.title3).foregroundStyle(.white.opacity(0.75))
                Spacer()
                Image(systemName: "lungs.fill").font(.system(size: 55, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.24)).accessibilityHidden(true)
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                if let last = journal.latestSmoke {
                    let minutes = max(0, Int(context.date.timeIntervalSince(last.date) / 60))
                    Label(minutes < 60 ? "距上次记录 \(minutes) 分钟" : "距上次记录 \(minutes / 60) 小时 \(minutes % 60) 分钟", systemImage: "clock")
                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                } else {
                    Text("从真实记录开始，慢慢看见自己的节奏").font(.caption).foregroundStyle(.white.opacity(0.8))
                }
            }
            Button(action: recordOne) {
                Label(pack == nil ? "添加当前烟包" : (remaining == 0 ? "这包已空，添加烟包" : "抽一根"),
                      systemImage: pack == nil || remaining == 0 ? "plus" : "plus.circle")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.glass).tint(.white)
            .disabled(diary.loadError != nil).accessibilityIdentifier("smokeOne")
        }
        .padding(24).foregroundStyle(.white)
        .background(LinearGradient(colors: [Color(red: 0.08, green: 0.35, blue: 0.29), Color(red: 0.08, green: 0.22, blue: 0.23)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 32))
        .animation(.snappy, value: today.smoked)
    }

    private var personalSummary: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("尼古丁标注累计", systemImage: "drop").font(.caption).foregroundStyle(.secondary)
                    Text(today.smoked == today.unknownNicotineCount ? "—" : "\(Theme.number(today.knownNicotineMG, decimals: 2)) mg")
                        .font(.title2.bold()).monospacedDigit()
                    Text(today.unknownNicotineCount > 0 ? "\(today.unknownNicotineCount) 根缺少标注值" : "按自己抽的根数累计")
                        .font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    Label("分给别人", systemImage: "person.2").font(.caption).foregroundStyle(.secondary)
                    Text("\(today.shared) 根").font(.title2.bold()).monospacedDigit()
                    Text("单独记录分烟数量").font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack(alignment: .top) {
                Text("自己抽的折算费用").font(.caption).foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    ForEach(SmokingCurrency.allCases) { currency in
                        if let cost = today.costs[currency] {
                            Text(cost, format: .currency(code: currency.rawValue)).font(.subheadline.weight(.semibold))
                        }
                    }
                    if today.costs.isEmpty { Text("—").font(.subheadline) }
                    if today.unpricedCount > 0 { Text("\(today.unpricedCount) 根缺少价格").font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }.contentCard()
    }

    private var currentPack: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("当前这一包", systemImage: "rectangle.stack").font(.headline)
                Spacer()
                Button("换一包") { sheet = .newPack }.font(.caption.weight(.semibold))
            }
            if let pack {
                HStack(spacing: 14) {
                    if let data = pack.photoJPEG, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: 54, height: 66)
                            .clipShape(.rect(cornerRadius: 12))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pack.product.name).font(.title3.bold())
                        HStack(spacing: 8) {
                            if let price = pack.product.pricePerPack { Text(price, format: .currency(code: pack.product.currency.rawValue)) }
                            Text("20 根 / 包")
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 4) {
                        Text("\(remaining)").font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("根剩余").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 10), spacing: 7) {
                    ForEach(0..<20) { index in
                        Capsule().fill(index < remaining ? Theme.accent : Theme.accent.opacity(0.09)).frame(height: 18)
                    }
                }.accessibilityElement(children: .ignore).accessibilityLabel("当前烟包剩余\(remaining)根，共20根")
                GlassEffectContainer {
                    HStack(spacing: 10) {
                        Button("分给别人", systemImage: "person.2") { sheet = .share }.disabled(remaining == 0)
                        Button("校准余量", systemImage: "slider.horizontal.3") { sheet = .stock }
                        Spacer(minLength: 0)
                        Button("编辑烟包", systemImage: "pencil") { sheet = .edit(pack) }.labelStyle(.iconOnly)
                    }.font(.caption).buttonStyle(.glass)
                }
            } else {
                HealthEmptyView(symbol: "rectangle.stack.badge.plus", title: "先记下手里的这一包", detail: "拍烟盒识别名称和标注值，填写价格及现在还剩几根。")
                Button("拍照添加烟包", systemImage: "camera") { sheet = .newPack }.buttonStyle(.glassProminent)
            }
        }.contentCard()
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
                Text("自己抽的、分出去的和余量校准都会留在这里。").font(.subheadline).foregroundStyle(.secondary)
            } else if let last = journal.events.last {
                Button("撤销上一条 · \(last.kind.title) \(last.count) 根", systemImage: "arrow.uturn.backward") {
                    do { try diary.removeSmokingEvent(last.id); errorMessage = nil; feedback = "已撤销上一条记录。" }
                    catch { errorMessage = error.localizedDescription }
                }.font(.caption).foregroundStyle(.secondary)
            }
        }.contentCard()
    }

    private func recordOne() {
        guard pack != nil, remaining > 0 else { sheet = .newPack; return }
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
                .foregroundStyle(event.kind == .smoked ? Theme.accent : Theme.fat).frame(width: 30)
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
