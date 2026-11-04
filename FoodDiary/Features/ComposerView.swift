import SwiftUI
import PhotosUI
import AVFoundation
import NutritionCore

struct ComposerView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(\.dismiss) private var dismiss
    private let initialRecord: MealRecord
    private let isEditing: Bool
    @State private var record: MealRecord
    @State private var reviewing: Bool
    @State private var photoItem: PhotosPickerItem?
    @State private var sheet: ComposerSheet?
    @State private var errorMessage: String?
    @State private var isAnalyzing = false
    @State private var photoLoadID: UUID?
    @State private var photoTask: Task<Void, Never>?
    @State private var analysisTask: Task<Void, Never>?
    @State private var dialog: ComposerDialog?

    init(record: MealRecord, isEditing: Bool) {
        initialRecord = record
        self.isEditing = isEditing
        _record = State(initialValue: record)
        _reviewing = State(initialValue: isEditing)
    }

    private var busy: Bool { isAnalyzing || photoLoadID != nil }
    private var dirty: Bool { record != initialRecord }

    var body: some View {
        NavigationStack {
            Form {
                mealMetadata
                if reviewing { reviewSections } else { inputSections }
                if let errorMessage { Section { ErrorNotice(message: errorMessage) } }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(reviewing ? (isEditing ? "编辑记录" : "确认这一餐") : "记录饮食")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        if dirty || busy { dialog = .discard } else { dismiss() }
                    }
                    .accessibilityIdentifier("closeComposer")
                }
                if reviewing && !isEditing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("输入") { reviewing = false; errorMessage = nil }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { primaryAction }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .camera:
                    CameraPicker { data in
                        sheet = nil
                        loadPhotoData(data)
                    } onCancel: { sheet = nil }
                    .ignoresSafeArea()
                case .food(let food):
                    FoodEditorView(food: food) { updated in
                        if let index = record.foods.firstIndex(where: { $0.id == updated.id }) {
                            record.foods[index] = updated
                        } else {
                            record.foods.append(updated)
                        }
                        reviewing = true
                        errorMessage = nil
                    }
                }
            }
            .confirmationDialog(dialog == .delete ? "删除这餐记录？" : "放弃尚未保存的修改？",
                                isPresented: Binding(get: { dialog != nil }, set: { if !$0 { dialog = nil } }),
                                titleVisibility: .visible) {
                if dialog == .delete {
                    Button("删除记录", role: .destructive, action: deleteRecord)
                } else {
                    Button("放弃修改", role: .destructive) {
                        analysisTask?.cancel()
                        photoTask?.cancel()
                        dismiss()
                    }
                }
                Button("继续编辑", role: .cancel) { dialog = nil }
            }
            .interactiveDismissDisabled(dirty || busy)
            .onChange(of: photoItem) { _, selection in
                guard let selection else { return }
                startPhotoLoad {
                    guard let data = try await selection.loadTransferable(type: Data.self) else {
                        throw DiaryError.invalidInput("无法读取这张照片，请重新选择。")
                    }
                    return data
                }
            }
            .onDisappear {
                analysisTask?.cancel()
                photoTask?.cancel()
            }
        }
    }

    private var mealMetadata: some View {
        Section {
            Picker("餐次", selection: $record.kind) {
                ForEach(MealKind.allCases) { kind in Text(kind.title).tag(kind) }
            }
            DatePicker("时间", selection: $record.date, in: ...Date.now)
        }
        .disabled(busy)
    }

    @ViewBuilder
    private var inputSections: some View {
        Section {
            TextField("例如：午餐一小碗米饭、番茄炒蛋，米饭吃了一半", text: Binding(
                get: { record.originalText },
                set: { record.updateInput(text: $0, photoJPEG: record.photoJPEG) }
            ), axis: .vertical)
                .lineLimit(4...8)
                .accessibilityIdentifier("mealDescription")
            if let data = record.photoJPEG, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxHeight: 230).frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 16))
                Button("移除照片", systemImage: "xmark.circle") {
                    record.updateInput(text: record.originalText, photoJPEG: nil)
                    photoItem = nil
                }
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 20) {
                Button("拍照", systemImage: "camera", action: openCamera)
                    .accessibilityIdentifier("takePhoto")
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Label("相册", systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("pickPhoto")
                Spacer()
                if photoLoadID != nil { ProgressView().accessibilityLabel("正在处理照片") }
            }
            .buttonStyle(.borderless)
        } header: {
            Text("吃了什么")
        } footer: {
            Text("可输入文字、选择照片，或一起补充。点击分析后，这些内容会发送给 DeepSeek，按你的 API 账户计费。")
        }
        .disabled(busy)

        Section {
            Button("手动添加食物", systemImage: "square.and.pencil") { sheet = .food(FoodItem()) }
                .accessibilityIdentifier("manualEntry")
            if !record.foods.isEmpty {
                Button("返回已有食物明细", systemImage: "list.bullet") { reviewing = true }
            }
        } footer: {
            Text("手动记录可直接填写包装标签上的热量，无需配置 API Key。")
        }
        .disabled(busy)
    }

    @ViewBuilder
    private var reviewSections: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text(Theme.number(record.nutrition.calories))
                    .font(.system(size: 42, weight: .medium, design: .rounded)).monospacedDigit()
                Text("千卡").foregroundStyle(.secondary)
                Spacer()
                Text(record.source.title).font(.caption).foregroundStyle(.secondary)
            }
            NutritionRow(nutrition: record.nutrition).padding(.vertical, 7)
        } header: {
            Text(isEditing ? "这一餐" : "确认食物与份量后保存")
        }

        Section {
            ForEach(record.foods) { food in
                Button { sheet = .food(food) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(food.name).foregroundStyle(.primary)
                            Text("\(Theme.number(food.grams, decimals: 1)) 克")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Theme.number(food.nutrition.calories)) 千卡").foregroundStyle(.primary)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 3)
                }
                .swipeActions { Button("移除", role: .destructive) { record.foods.removeAll { $0.id == food.id } } }
            }
            Button("添加食物", systemImage: "plus") { sheet = .food(FoodItem()) }
        } header: {
            Text("食物明细 · 点击调整")
        } footer: {
            Text("调整克数会自动重算。向左滑动食物可移除。")
        }

        if record.source != .manual {
            Section("估算说明") {
                if !record.summary.isEmpty { Text(record.summary).font(.subheadline) }
                ForEach(Array(record.assumptions.enumerated()), id: \.offset) { _, assumption in
                    Label(assumption, systemImage: "info.circle")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text("AI 无法从图片精确测量重量、油和糖，营养数值为估算，请结合实际食用量核对。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }

        if !record.originalText.isEmpty || record.photoJPEG != nil {
            Section {
                DisclosureGroup("原始记录") {
                    if !record.originalText.isEmpty { Text(record.originalText).font(.subheadline) }
                    if let data = record.photoJPEG, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 230)
                    }
                    if let model = record.model { Text(model).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }

        if isEditing {
            Section { Button("删除这餐记录", role: .destructive) { dialog = .delete } }
        }
    }

    private var primaryAction: some View {
        VStack(spacing: 8) {
            if isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("DeepSeek 正在分析这一餐…").font(.subheadline)
                    Spacer()
                    Button("取消") { analysisTask?.cancel() }
                }
                .padding(.horizontal, 6)
            }
            Button {
                if reviewing { saveRecord() } else { analyze() }
            } label: {
                Label(reviewing ? "确认并保存" : "AI 分析这一餐", systemImage: reviewing ? "checkmark" : "sparkles")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .disabled(busy || (reviewing && record.foods.isEmpty)
                      || (!reviewing && record.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && record.photoJPEG == nil))
            .accessibilityIdentifier(reviewing ? "saveMeal" : "analyzeMeal")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func analyze() {
        errorMessage = nil
        isAnalyzing = true
        let input = record.originalText
        let image = record.photoJPEG
        analysisTask = Task { @MainActor in
            defer { isAnalyzing = false }
            do {
                let key = try KeychainStore.load()
                let result = try await DeepSeekClient().analyze(text: input, imageJPEG: image, apiKey: key)
                try Task.checkCancellation()
                record.foods = result.foods
                record.summary = result.summary
                record.assumptions = result.assumptions
                record.model = result.model
                record.source = image == nil ? .text : .photo
                reviewing = true
            } catch is CancellationError {
                // A cancelled request leaves the current input untouched.
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func saveRecord() {
        do {
            try diary.save(record)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func deleteRecord() {
        do {
            try diary.delete(record)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = "当前设备无法使用相机，请从相册选择照片。"
            return
        }
        Task { @MainActor in
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { sheet = .camera }
            else { errorMessage = "相机权限尚未开启，可在 iPhone「设置」中允许食记访问相机，或从相册选图。" }
        }
    }

    private func loadPhotoData(_ data: Data) { startPhotoLoad { data } }

    private func startPhotoLoad(_ load: @escaping @Sendable () async throws -> Data) {
        photoTask?.cancel()
        let id = UUID()
        photoLoadID = id
        errorMessage = nil
        photoTask = Task { @MainActor in
            defer { if photoLoadID == id { photoLoadID = nil } }
            do {
                let data = try await load()
                try Task.checkCancellation()
                let jpeg = try await Task.detached(priority: .userInitiated) { try PhotoInput.prepareJPEG(data) }.value
                try Task.checkCancellation()
                guard photoLoadID == id else { return }
                record.updateInput(text: record.originalText, photoJPEG: jpeg)
            } catch is CancellationError {
                // Newer photo selections own the preview and loading state.
            } catch {
                if photoLoadID == id { errorMessage = error.localizedDescription }
            }
        }
    }
}

private enum ComposerSheet: Identifiable {
    case camera
    case food(FoodItem)
    var id: String {
        switch self {
        case .camera: "camera"
        case .food(let food): food.id.uuidString
        }
    }
}

private enum ComposerDialog { case discard, delete }
