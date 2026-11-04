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
    @State private var errorMessage: String?
    @State private var loadingID: UUID?
    @State private var analysisID: UUID?
    @State private var photoTask: Task<Void, Never>?
    @State private var analysisTask: Task<Void, Never>?

    init(pack: CigarettePack? = nil) {
        original = pack
        let savedCurrency = SmokingCurrency(rawValue: UserDefaults.standard.string(forKey: "smokingCurrency") ?? "CNY") ?? .cny
        _fields = State(initialValue: CigaretteProductDraft(product: pack?.product, currency: savedCurrency))
        _openingCount = State(initialValue: pack?.openingCount ?? 20)
        _photoJPEG = State(initialValue: pack?.photoJPEG)
    }

    private var busy: Bool { loadingID != nil || analysisID != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    photoInput.disabled(busy)
                    productFields.disabled(busy)
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
            .navigationTitle(original == nil ? "添加当前烟包" : "编辑烟包资料")
            .navigationBarTitleDisplayMode(.inline)
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
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.glassProminent)
                        .disabled(busy || fields.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || diary.loadError != nil)
                        .accessibilityIdentifier("saveSmokingPack")
                }.padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
            }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .camera:
                    CameraPicker { data in sheet = nil; loadPhoto { data } } onCancel: { sheet = nil }
                        .ignoresSafeArea()
                case .settings: GeneralSettingsView(isPresented: true)
                }
            }
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
            Label("拍烟盒，AI 帮你读", systemImage: "sparkles").font(.headline).foregroundStyle(Theme.accent)
            Text("拍清品牌、侧面的烟气烟碱标注。价格可以补一句，或拍上价签。")
                .font(.subheadline).foregroundStyle(.secondary)
            TextField("例如：这包买了30元，标注烟碱量0.8毫克", text: $description, axis: .vertical)
                .lineLimit(2...4).accessibilityIdentifier("cigaretteDescription")
            if let photoJPEG, let image = UIImage(data: photoJPEG) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 230).frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 16))
                Button("移除照片", systemImage: "xmark.circle") { self.photoJPEG = nil; photoItem = nil }
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("拍照", systemImage: "camera", action: openCamera)
                PhotosPicker(selection: $photoItem, matching: .images) { Label("相册", systemImage: "photo") }
                if loadingID != nil { ProgressView() }
            }.font(.subheadline).buttonStyle(.bordered)
            Button("AI 识别烟盒", systemImage: "viewfinder", action: analyze)
                .font(.subheadline.weight(.semibold)).buttonStyle(.borderedProminent)
                .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photoJPEG == nil)
                .accessibilityIdentifier("analyzeSmokingPack")
            Text("点击识别后，文字和处理后的照片将发送给 DeepSeek，费用记入你的 API 账户。识别只补全空缺资料，可分次拍正面和侧面。需要重新识别某项时，先清空该项。")
                .font(.caption2).foregroundStyle(.secondary)
        }.contentCard()
    }

    private var productFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("确认这包的信息").font(.headline)
            TextField("香烟名称 / 品牌规格", text: $fields.name).accessibilityIdentifier("cigaretteName")
            Divider()
            numberField("每包价格", text: $fields.priceText, unit: fields.currency.rawValue)
            Picker("货币", selection: $fields.currency) {
                ForEach(SmokingCurrency.allCases) { Text($0.title).tag($0) }
            }.font(.subheadline)
            Divider()
            numberField("每根尼古丁标注", text: $fields.nicotineText, unit: "mg")
            Text("价格和标注值可以留空，之后补充。请读取烟气烟碱量一项。")
                .font(.caption).foregroundStyle(.secondary)
            if original == nil {
                Divider()
                Stepper(value: $openingCount, in: 0...20) {
                    LabeledContent("现在这包还剩", value: "\(openingCount) 根")
                }.font(.subheadline)
                Text("完整一包20根，可从手中真实余量开始。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("修正资料会重新计算这包已有记录的标注累计和费用。实际余量可在戒烟主页校准。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.contentCard()
    }

    private func numberField(_ title: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            TextField("选填", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .frame(maxWidth: 120).accessibilityLabel(title)
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
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
                fields.fillMissing(from: result)
            } catch is CancellationError {
            } catch { if analysisID == id { errorMessage = error.localizedDescription } }
        }
    }

    private func cancelAnalysis() { analysisID = nil; analysisTask?.cancel() }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = "当前无法使用相机，请从相册选择照片。"
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
            UserDefaults.standard.set(product.currency.rawValue, forKey: "smokingCurrency")
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
