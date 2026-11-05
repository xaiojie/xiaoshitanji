import SwiftUI
import PhotosUI
import NutritionCore

struct MealMetadataView: View {
    @Binding var kind: MealKind
    @Binding var date: Date
    @State private var expanded = false

    private var latestRecordDate: Date {
        Calendar.current.dateInterval(of: .day, for: .now)?.end.addingTimeInterval(-1) ?? .now
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("餐次", selection: $kind) {
                    ForEach(MealKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                DatePicker("用餐时间", selection: $date, in: ...latestRecordDate)
                    .font(.subheadline)
                Text(kind == .snack ? "加餐按记录时刻预填，可点选调整。" : "已按常用用餐时间预填，可点选调整。")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
            }.padding(.top, 14)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: kind.symbol).foregroundStyle(Theme.olive)
                Text(kind.title).fontWeight(.bold)
                Spacer()
                Text(date.formatted(.dateTime.month().day().hour().minute()))
                    .foregroundStyle(Theme.mutedInk).font(.caption)
            }
        }
        .font(.subheadline).padding(16)
        .background(Theme.softYellow.opacity(0.5), in: .rect(cornerRadius: 20))
    }
}

struct MealInputView: View {
    @Binding var text: String
    @Binding var mode: FoodAnalysisMode
    @Binding var photoItem: PhotosPickerItem?
    let photos: [Data]
    let loadingPhoto: Bool
    let onCamera: () -> Void
    let onRemovePhoto: (Int) -> Void
    @State private var transcriber = SpeechTranscriber()

    private var full: Bool { photos.count >= DeepSeekClient.maxPhotos }

    private var photoHint: String {
        if photos.count == 1 { return "再拍一张包装正面或营养成分表，能量会更准。" }
        return "已选 \(photos.count) 张，最多 \(DeepSeekClient.maxPhotos) 张：正面、营养表、剩下的食物。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            BrandSegments(options: FoodAnalysisMode.allCases.map { ($0, $0.title) }, selection: $mode)
            if photos.isEmpty {
                Button(action: onCamera) {
                    VStack(spacing: 15) {
                        Image(systemName: "viewfinder").font(.system(size: 54, weight: .light)).foregroundStyle(Theme.accent)
                        Text(mode == .label ? "对准营养成分表" : "拍下碗里的这一餐")
                            .font(.title3.bold()).foregroundStyle(Theme.surface)
                        Text(mode == .label ? "拍清单位、每份营养值和净含量" : "轻点直接打开相机，AI 根据食物、碗型和装满程度估算")
                            .font(.caption).foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center).padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity).frame(height: 220)
                    .background(Theme.darkGradient, in: .rect(cornerRadius: 26))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode == .label ? "拍照识别营养成分表" : "拍照记录这一餐")
                .accessibilityHint("打开相机")
                .accessibilityIdentifier("takePhotoCard")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
                            ZStack(alignment: .topTrailing) {
                                ScanPhotoPreview(data: data, height: 170)
                                    .frame(width: 150)
                                Button {
                                    onRemovePhoto(index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(Theme.surface, Theme.ink.opacity(0.55))
                                }
                                .buttonStyle(.plain)
                                .padding(6)
                                .accessibilityLabel("移除第 \(index + 1) 张照片")
                                .accessibilityIdentifier("removePhoto\(index)")
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                Text(photoHint)
                    .font(.caption).foregroundStyle(Theme.mutedInk)
            }

            HStack(spacing: 12) {
                Button(action: onCamera) {
                    Label(photos.isEmpty ? "拍照" : (full ? "已满 3 张" : "再加一张"), systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity, minHeight: 42)
                }.yellowAction()
                .disabled(full)
                .accessibilityIdentifier("takePhoto")
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Label("相册选图", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 42)
                }.buttonStyle(.glass)
                .disabled(full)
                .accessibilityIdentifier("pickPhoto")
            }.font(.subheadline.bold())
            if loadingPhoto { ProgressView("正在处理照片…").font(.caption) }

            VStack(alignment: .leading, spacing: 13) {
                Label("吃了多少？说一句就好", systemImage: "text.bubble").font(.headline)
                HStack(alignment: .top, spacing: 10) {
                    TextField("比如：牛奶喝了半盒，或一碗牛肉粉只吃了面", text: $text, axis: .vertical)
                        .lineLimit(2...5).font(.subheadline).lineSpacing(4)
                        .accessibilityIdentifier("mealDescription")
                    Button {
                        Task { await transcriber.toggle() }
                    } label: {
                        Image(systemName: transcriber.isRecording ? "stop.circle.fill" : "mic.fill")
                            .font(.title3)
                            .foregroundStyle(transcriber.isRecording ? Theme.gold : Theme.olive)
                            .symbolEffect(.pulse, isActive: transcriber.isRecording)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(transcriber.isRecording ? "停止语音输入" : "语音输入")
                    .accessibilityIdentifier("dictateMeal")
                }
                if transcriber.isRecording {
                    Label("正在听…说完点一下停止，文字会填进输入框。", systemImage: "waveform")
                        .font(.caption).foregroundStyle(Theme.olive)
                }
                if let error = transcriber.errorMessage {
                    Text(error).font(.caption).foregroundStyle(Theme.gold)
                }
                Text("也可以只用文字记餐，份量和营养由 AI 估算。")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["牛奶喝了半盒", "一小碗米饭", "面吃完，汤没喝"], id: \.self) { example in
                            Button(example) { text = example }
                                .font(.caption).buttonStyle(.bordered)
                        }
                    }
                }
            }.contentCard()
            .onChange(of: transcriber.transcript) { _, value in
                if !value.isEmpty { text = value }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield").foregroundStyle(Theme.olive)
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI 分析免费使用。点击分析后，文字和压缩后的照片会经小食痰记服务器转交 DeepSeek 处理。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
        }
    }
}
