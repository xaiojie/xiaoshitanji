import SwiftUI
import PhotosUI
import AVFoundation
import NutritionCore

private enum SmokingEditorSheet: String, Identifiable {
    case camera, settings
    var id: Self { self }
}

struct SmokingPackEditorView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(\.dismiss) private var dismiss
    let original: CigarettePack?
    @State private var fields: CigaretteProductDraft
    @State private var openingCount: Int
    @State private var description = ""
    @State private var photoJPEG: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var sheet: SmokingEditorSheet?
    @State private var showingPhotoPicker = false
    @State private var errorMessage: String?
    @State private var loadingID: UUID?
    @State private var analysisID: UUID?
    @State private var photoTask: Task<Void, Never>?
    @State private var analysisTask: Task<Void, Never>?

    init(pack: CigarettePack? = nil) {
        original = pack
        _fields = State(initialValue: CigaretteProductDraft(product: pack?.product, currency: .cny))
        _openingCount = State(initialValue: pack?.openingCount ?? 20)
        _photoJPEG = State(initialValue: pack?.photoJPEG)
    }

    private var busy: Bool { loadingID != nil || analysisID != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    photoInput.disabled(busy)
                    recognitionResult
                    packQuantity.disabled(busy)
                    if !fields.notes.isEmpty {
                        Label(fields.notes, systemImage: "text.viewfinder").font(.caption).foregroundStyle(.secondary).contentCard()
                    }
                    if let errorMessage {
                        ErrorNotice(message: errorMessage).contentCard()
                        Button("打开通用设置", systemImage: "gearshape") { sheet = .settings }.font(.subheadline)
                    }
                    NicotineExplanation()
                }.padding(20)
            }
            .background(Theme.background).scrollDismissesKeyboard(.interactively)
            .navigationTitle("AI 识别烟盒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if analysisID != nil {
                        HStack {
                            ProgressView()
                            Text("正在读取烟盒信息…").font(.caption)
                            Spacer()
                            Button("取消识别", action: cancelAnalysis).font(.caption)
                        }
                    }
                    Button(original == nil ? "确认并保存烟包" : "保存资料", systemImage: "checkmark", action: save)
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44).yellowAction()
                        .disabled(busy || fields.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || diary.loadError != nil)
                        .accessibilityIdentifier("saveSmokingPack")
                }.padding(.horizontal, 20).padding(.vertical, 12).background(Theme.background)
            }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .camera:
                    CameraPicker { data in sheet = nil; loadPhoto { data } } onCancel: { sheet = nil }
                        .ignoresSafeArea()
                case .settings: GeneralSettingsView(isPresented: true)
                }
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, selection in
                guard let selection else { return }
                loadPhoto {
                    guard let data = try await selection.loadTransferable(type: Data.self) else {
                        throw DiaryError.invalidInput("无法读取这张照片，请重新选择。")
                    }
                    return data
                }
            }
            .interactiveDismissDisabled(busy)
            .onDisappear { cancelAnalysis(); loadingID = nil; photoTask?.cancel() }
        }
    }

    private var photoInput: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let photoJPEG {
                ScanPhotoPreview(data: photoJPEG, height: 250)
                Button("移除照片", systemImage: "xmark.circle") { self.photoJPEG = nil; photoItem = nil }
                    .font(.caption).foregroundStyle(Theme.mutedInk)
            } else {
                VStack(spacing: 15) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 50, weight: .light)).foregroundStyle(Theme.accent)
                    Text("拍好，AI 自动识别").font(.title3.bold()).foregroundStyle(Theme.surface)
                    Text("先拍正面，再补侧面标注和价签")
                        .font(.caption).foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity).frame(height: 210)
                .background(Theme.darkGradient, in: .rect(cornerRadius: 26))
            }
            Button(action: openCamera) {
                Label(photoJPEG == nil ? "扫描烟盒" : "继续扫描烟盒", systemImage: "camera.viewfinder")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 46)
            }
            .yellowAction().accessibilityIdentifier("analyzeSmokingPack")
            HStack(spacing: 12) {
                PhotosPicker(selection: $photoItem, matching: .images) { Label("相册导入", systemImage: "photo") }
                Spacer()
                if loadingID != nil { ProgressView() }
            }.font(.subheadline).buttonStyle(.glass)
            VStack(alignment: .leading, spacing: 13) {
                Label("补充一句，AI 帮你改", systemImage: "text.bubble").font(.headline)
                TextField("例如：这包买了30元，或清空错误的尼古丁值", text: $description, axis: .vertical)
                    .lineLimit(2...4).font(.subheadline).accessibilityIdentifier("cigaretteDescription")
                if photoJPEG != nil || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("更新识别结果", systemImage: "sparkles", action: analyze)
                        .font(.subheadline.weight(.semibold)).buttonStyle(.bordered)
                        .accessibilityIdentifier("updateSmokingPackRecognition")
                }
            }.contentCard()
            Text("扫描或导入图片后，AI 会自动读取。也可以说“这包买了30元”“价格改成25元”或“清空错误的尼古丁值”，再更新结果。识别时文字和照片会发送给 DeepSeek，费用记入你的 API 账户。")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var recognitionResult: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("AI 识别结果", systemImage: "sparkles").font(.headline)
                Spacer()
                Image("MilkFrogPeek").resizable().scaledToFit().frame(width: 50, height: 48).accessibilityHidden(true)
            }
            Text(fields.name.isEmpty ? "等待识别烟盒正面" : fields.name).font(.title3.bold())
            LabeledContent("每包价格") {
                if let price = Double(fields.priceText) {
                    Text(price, format: .currency(code: fields.currency.rawValue))
                } else { Text("待补充价签或购买价") }
            }
            LabeledContent("每根尼古丁标注", value: fields.nicotineText.isEmpty ? "待补拍侧面标注" : "\(fields.nicotineText) mg")
            Text("结果集中保存在这里。看不清的部分可补拍，或用上方的一句话说明来更新。")
                .font(.caption).foregroundStyle(.secondary)
        }.font(.subheadline).padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.softYellow, in: .rect(cornerRadius: 26))
    }

    private var packQuantity: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("当前烟包", systemImage: "rectangle.stack").font(.headline)
            if original == nil {
                Stepper(value: $openingCount, in: 0...20) {
                    LabeledContent("现在这包还剩", value: "\(openingCount) 根")
                }.font(.subheadline)
                Text("完整一包20根，可从手中真实余量开始。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("重新识别会更新本包记录的标注累计与费用。实际余量可在戒烟主页校准。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.contentCard()
    }

    private func loadPhoto(_ load: @escaping @Sendable () async throws -> Data) {
        guard analysisID == nil else { return }
        photoTask?.cancel()
        let id = UUID()
        loadingID = id
        photoTask = Task { @MainActor in
            defer { if loadingID == id { loadingID = nil } }
            do {
                let data = try await load()
                try Task.checkCancellation()
                let jpeg = try await Task.detached { try PhotoInput.prepareJPEG(data) }.value
                try Task.checkCancellation()
                guard loadingID == id else { return }
                photoJPEG = jpeg
                errorMessage = nil
                loadingID = nil
                analyze()
            } catch is CancellationError {
            } catch { if loadingID == id { errorMessage = error.localizedDescription } }
        }
    }

    private func analyze() {
        guard !busy else { return }
        let id = UUID()
        let text = description
        let photo = photoJPEG
        let selectedCurrency = fields.currency
        analysisID = id
        errorMessage = nil
        analysisTask = Task { @MainActor in
            defer { if analysisID == id { analysisID = nil } }
            do {
                let key = try KeychainStore.load()
                let result = try await DeepSeekClient().recognizeCigarette(text: text, imageJPEG: photo,
                    apiKey: key, currency: selectedCurrency)
                try Task.checkCancellation()
                guard analysisID == id else { return }
                fields.applyRecognition(result)
            } catch is CancellationError {
            } catch { if analysisID == id { errorMessage = error.localizedDescription } }
        }
    }

    private func cancelAnalysis() { analysisID = nil; analysisTask?.cancel() }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showingPhotoPicker = true
            return
        }
        Task { @MainActor in
            if await AVCaptureDevice.requestAccess(for: .video) { sheet = .camera }
            else { errorMessage = "请在 iPhone 设置中允许相机访问，或从相册选择照片。" }
        }
    }

    private func save() {
        do {
            let product = try fields.makeProduct()
            let pack = CigarettePack(id: original?.id ?? UUID(), product: product,
                openedAt: original?.openedAt ?? .now, openingCount: original?.openingCount ?? openingCount, photoJPEG: photoJPEG)
            if original == nil { try diary.openSmokingPack(pack) }
            else { try diary.updateSmokingPack(pack) }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
