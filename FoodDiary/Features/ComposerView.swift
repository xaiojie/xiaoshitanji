import SwiftUI
import PhotosUI
import AVFoundation
import NutritionCore

struct ComposerView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MealDraft
    @State private var photoItem: PhotosPickerItem?
    @State private var sheet: ComposerSheet?
    @State private var dialog: ComposerDialog?
    @State private var savedTemplateName: String?

    init(record: MealRecord, isEditing: Bool) {
        _draft = State(initialValue: MealDraft(record: record, isEditing: isEditing))
    }

    private var hasCorrection: Bool { !draft.correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    MealMetadataView(kind: Binding(
                        get: { draft.record.kind },
                        set: { kind in
                            if kind != draft.record.kind { draft.record.usePresetTime(for: kind) }
                        }
                    ), date: $draft.record.date)
                        .disabled(draft.busy)
                    if draft.reviewing {
                        MealResultView(record: draft.record) { sheet = .food($0) }
                            .disabled(draft.busy)
                        HStack(spacing: 10) {
                            Button("添加食物", systemImage: "plus") { sheet = .quickAdd }
                            Button("存为常吃", systemImage: "star") { saveTemplate() }
                        }
                        .font(.subheadline)
                        .buttonStyle(.glass)
                        .disabled(draft.busy)
                        if let savedTemplateName {
                            Label(savedTemplateName, systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(Theme.olive)
                        }
                        MealCorrectionView(text: $draft.correction, busy: draft.busy) {
                            draft.refine(draft.correction)
                        }
                        EstimateExplanationView(record: draft.record)
                        if draft.isEditing {
                            Button("删除这餐记录", role: .destructive) { dialog = .delete }
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .disabled(draft.busy)
                        }
                    } else {
                        MealInputView(
                            text: Binding(get: { draft.record.originalText }, set: draft.updateText),
                            mode: Binding(get: { draft.record.analysisMode ?? .automatic }, set: draft.updateMode),
                            photoItem: $photoItem, photoJPEG: draft.record.photoJPEG,
                            loadingPhoto: draft.photoLoadID != nil,
                            onCamera: openCamera,
                            onRemovePhoto: { draft.removePhoto(); photoItem = nil },
                            onSettings: { sheet = .settings }
                        )
                        .disabled(draft.busy)
                        Button("手动填写 / 常吃 / 最近吃过", systemImage: "square.and.pencil") { sheet = .quickAdd }
                            .font(.subheadline).buttonStyle(.glass)
                            .disabled(draft.busy)
                        if !draft.record.foods.isEmpty {
                            Button("返回已识别的食物", systemImage: "list.bullet") { draft.reviewing = true }
                                .disabled(draft.busy)
                        }
                    }
                    if let message = draft.errorMessage {
                        VStack(alignment: .leading, spacing: 12) {
                            ErrorNotice(message: message)
                            if draft.requiresKey {
                                Button("配置 DeepSeek API Key", systemImage: "key") { sheet = .settings }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .contentCard()
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(draft.reviewing ? "这一餐的分析" : "AI 记饮食")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", action: close).accessibilityIdentifier("closeComposer")
                }
                if draft.reviewing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("重新输入") { draft.reviewing = false; draft.errorMessage = nil }
                            .disabled(draft.busy)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { primaryAction }
            .sheet(item: $sheet, content: sheetContent)
            .alert(dialog == .delete ? "删除这餐记录？" : "放弃尚未保存的修改？",
                isPresented: Binding(get: { dialog != nil }, set: { if !$0 { dialog = nil } }),
                presenting: dialog) { action in
                if action == .delete { Button("删除记录", role: .destructive, action: deleteRecord) }
                else { Button("放弃修改", role: .destructive) { draft.cancelAll(); dismiss() } }
                Button("继续编辑", role: .cancel) { dialog = nil }
            } message: { action in
                Text(action == .delete ? "这条饮食记录会从本机删除。" : "当前修改尚未保存，离开后需要重新输入。")
            }
            .interactiveDismissDisabled(draft.dirty || draft.busy)
            .onChange(of: photoItem) { _, selection in
                if let selection { draft.choosePhoto(selection) }
            }
            .onDisappear { draft.cancelAll() }
        }
    }

    private var primaryAction: some View {
        VStack(spacing: 10) {
            if draft.isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(draft.isRefining ? "正在按你的描述重新计算…" : "正在识别食物、估算份量和营养…")
                        .font(.caption)
                    Spacer()
                    Button("取消", action: draft.cancelAnalysis).font(.subheadline)
                }
            }
            Button(action: submit) {
                Label(primaryTitle, systemImage: draft.reviewing && !hasCorrection ? "checkmark" : "sparkles")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .yellowAction()
            .disabled(draft.busy || (draft.reviewing && draft.record.foods.isEmpty && !hasCorrection)
                || (!draft.reviewing && draft.record.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && draft.record.photoJPEG == nil))
            .accessibilityIdentifier(draft.reviewing && !hasCorrection ? "saveMeal" : "analyzeMeal")
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Theme.background)
    }

    private var primaryTitle: String {
        if !draft.reviewing { return "让 AI 分析这一餐" }
        return hasCorrection ? "让 AI 更新这一餐" : "保存这餐饮食"
    }

    @ViewBuilder
    private func sheetContent(_ destination: ComposerSheet) -> some View {
        switch destination {
        case .camera:
            CameraPicker { data in sheet = nil; draft.loadPhotoData(data) } onCancel: { sheet = nil }
                .ignoresSafeArea()
        case .food(let food):
            FoodPortionView(food: food, onUpdate: draft.replaceFood,
                onCorrection: { instruction in sheet = nil; draft.refine(instruction) },
                onRemove: { draft.removeFood(food) })
        case .quickAdd:
            QuickAddView(
                onFood: { draft.addFood($0) },
                onTemplate: { draft.apply(template: $0) },
                onRecord: { draft.copy(record: $0) })
        case .settings:
            GeneralSettingsView(isPresented: true)
        }
    }

    private func submit() {
        if !draft.reviewing { draft.analyze() }
        else if hasCorrection { draft.refine(draft.correction) }
        else { saveRecord() }
    }

    private func close() {
        if draft.dirty || draft.busy { dialog = .discard }
        else { dismiss() }
    }

    private func saveRecord() {
        do { try diary.save(draft.record); dismiss() }
        catch { draft.errorMessage = error.localizedDescription }
    }

    private func saveTemplate() {
        guard !draft.record.foods.isEmpty else {
            draft.errorMessage = "先有至少一种食物，才能存成常吃组合。"
            return
        }
        do {
            try diary.saveTemplate(MealTemplate(record: draft.record))
            savedTemplateName = "已存为常吃「\(draft.record.foodNames)」"
        } catch {
            draft.errorMessage = error.localizedDescription
        }
    }

    private func deleteRecord() {
        do { try diary.delete(draft.record); dismiss() }
        catch { draft.errorMessage = error.localizedDescription }
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            draft.errorMessage = "当前无法使用相机，请从相册选择照片。"
            return
        }
        Task { @MainActor in
            if await AVCaptureDevice.requestAccess(for: .video) { sheet = .camera }
            else { draft.errorMessage = "请在 iPhone「设置」中允许小食痰记访问相机，或从相册选择照片。" }
        }
    }
}

private enum ComposerSheet: Identifiable {
    case camera, settings, quickAdd
    case food(FoodItem)
    var id: String {
        switch self {
        case .camera: "camera"
        case .settings: "settings"
        case .quickAdd: "quickAdd"
        case .food(let food): food.id.uuidString
        }
    }
}

private enum ComposerDialog { case discard, delete }
