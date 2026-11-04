import SwiftUI
import Charts
import NutritionCore

struct WeightEditRequest: Identifiable {
    let id = UUID()
    var record: WeightRecord?
}

struct WeightHistoryView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(HealthDataModel.self) private var health
    @State private var editing: WeightEditRequest?
    @State private var deleting: WeightRecord?
    @State private var errorMessage: String?

    private var records: [WeightRecord] {
        (diary.document.weights + health.weights).sorted {
            if $0.date == $1.date { return $0.id.uuidString > $1.id.uuidString }
            return $0.date > $1.date
        }
    }
    private var latest: WeightRecord? { WeightRecord.latest(in: records) }
    private var chartRecords: [WeightRecord] { Array(records.prefix(30).reversed()) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("最近体重").font(.headline)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(latest.map { Theme.number($0.kilograms, decimals: 2) } ?? "—")
                            .font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("公斤").foregroundStyle(.secondary)
                        Spacer()
                        if let target = diary.document.profile.targetWeightKG {
                            VStack(alignment: .trailing, spacing: 5) {
                                Text("目标体重").font(.caption).foregroundStyle(.secondary)
                                Text("\(Theme.number(target, decimals: 2)) 公斤").font(.subheadline.bold())
                            }
                        }
                    }
                    if let latest {
                        Text("\(latest.date.formatted(.dateTime.year().month().day().hour().minute())) · \(latest.source.title)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("记录体重", systemImage: "plus") { editing = WeightEditRequest() }
                        .yellowAction().accessibilityIdentifier("addWeight")
                }.contentCard()

                if !records.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("最近 \(chartRecords.count) 次测量").font(.headline)
                        Chart(chartRecords) { record in
                            LineMark(x: .value("时间", record.date), y: .value("公斤", record.kilograms))
                                .foregroundStyle(Theme.olive)
                            PointMark(x: .value("时间", record.date), y: .value("公斤", record.kilograms))
                                .foregroundStyle(Theme.olive).symbolSize(35)
                                .accessibilityLabel(record.date.formatted(.dateTime.month().day().hour().minute()))
                                .accessibilityValue("\(Theme.number(record.kilograms, decimals: 2)) 公斤，\(record.source.title)")
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month().day()) } }
                        .frame(height: 190)
                    }.contentCard()
                }

                HStack {
                    Text("测量记录").font(.title3.bold())
                    Spacer()
                    Text("\(records.count) 条").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 4)
                if records.isEmpty {
                    HealthEmptyView(symbol: "scalemass", title: "从一次测量开始", detail: "手动记录，或在通用设置中连接 Apple 健康读取体重。")
                        .contentCard()
                }
                ForEach(records) { record in
                    HStack(spacing: 14) {
                        Image(systemName: record.source == .manual ? "scalemass.fill" : "heart.fill")
                            .foregroundStyle(record.source == .manual ? Theme.olive : .pink)
                            .frame(width: 38, height: 38)
                            .background(Theme.accent.opacity(0.07), in: .circle)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(Theme.number(record.kilograms, decimals: 2)) 公斤").font(.headline)
                            Text(record.date.formatted(.dateTime.year().month().day().hour().minute()))
                                .font(.caption).foregroundStyle(.secondary)
                            Text(record.source.title).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if record.source == .manual {
                            Menu("管理体重记录", systemImage: "ellipsis") {
                                Button("编辑", systemImage: "pencil") { editing = WeightEditRequest(record: record) }
                                Button("删除", systemImage: "trash", role: .destructive) { deleting = record }
                            }
                            .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                        }
                    }.contentCard()
                }
                Text("手动记录可编辑或删除。Apple 健康中的测量可前往健康 App 管理，返回后下拉刷新。")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
                if let error = diary.loadError ?? errorMessage { ErrorNotice(message: error).contentCard() }
            }.padding(20)
        }
        .background(Theme.background).navigationTitle("体重记录").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: $editing) { WeightEditorView(record: $0.record) }
        .alert("删除这条体重记录？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除", role: .destructive) {
                guard let deleting else { return }
                do { try diary.deleteWeight(deleting); errorMessage = nil }
                catch { errorMessage = error.localizedDescription }
                self.deleting = nil
            }
        }
        .refreshable { await health.refresh() }
    }
}

struct WeightEditorView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(\.dismiss) private var dismiss
    let record: WeightRecord?
    @State private var weightText: String
    @State private var date: Date
    @State private var errorMessage: String?

    init(record: WeightRecord? = nil) {
        self.record = record
        _weightText = State(initialValue: HealthMeasurementInput.format(record?.kilograms))
        _date = State(initialValue: record?.date ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("体重")
                        Spacer()
                        TextField("填写测量值", text: $weightText).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).accessibilityIdentifier("weightMeasurement")
                        Text("公斤").foregroundStyle(.secondary)
                    }
                    DatePicker("测量时间", selection: $date, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                } footer: { Text("记录一次真实测量。即使数值相同，也会保留这次新的测量时间。") }
                if let errorMessage { Section { ErrorNotice(message: errorMessage) } }
            }
            .scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle(record == nil ? "记录体重" : "编辑体重")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save).disabled(diary.loadError != nil)
                        .accessibilityIdentifier("saveWeight")
                }
            }
        }
    }

    private func save() {
        do {
            guard let kilograms = try HealthMeasurementInput.parse(weightText),
                  record?.source != .appleHealth else {
                throw DiaryError.invalidInput("请填写有效的体重数值。")
            }
            let weight = WeightRecord(id: record?.id ?? UUID(), date: date, kilograms: kilograms)
            try diary.saveWeight(weight)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
