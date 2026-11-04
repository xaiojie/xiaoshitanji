import SwiftUI
import PhotosUI
import NutritionCore

struct MealMetadataView: View {
    @Binding var kind: MealKind
    @Binding var date: Date

    private var latestRecordDate: Date {
        Calendar.current.dateInterval(of: .day, for: .now)?.end.addingTimeInterval(-1) ?? .now
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                MealIcon(kind: kind, size: 36)
                Picker("餐次", selection: $kind) {
                    ForEach(MealKind.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().tint(.primary)
                Spacer()
            }
            DatePicker("用餐时间", selection: $date, in: ...latestRecordDate)
                .font(.subheadline)
            Text(kind == .snack ? "加餐按记录时刻预填，可点选调整。" : "已按常用用餐时间预填，可点选调整。")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentCard()
    }
}

struct MealInputView: View {
    @Binding var text: String
    @Binding var mode: FoodAnalysisMode
    @Binding var photoItem: PhotosPickerItem?
    let photoJPEG: Data?
    let loadingPhoto: Bool
    let onCamera: () -> Void
    let onRemovePhoto: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Label("AI 饮食助手", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                Text("这一餐，吃了什么？").font(.title2.bold())
                Text("商品拍营养成分表，正餐拍碗里的食物。再说一句吃了多少，AI 帮你分析。")
                    .font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
            }
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 18) {
                Picker("分析方式", selection: $mode) {
                    ForEach(FoodAnalysisMode.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Text(mode == .label ? "拍清每100克/毫升或每份的营养值，尽量带上净含量。" : "可补充大碗、小碗、装满程度，以及饭、菜、汤实际吃了多少。")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("比如：这盒牛奶喝了半盒，或一碗牛肉粉只吃了面", text: $text, axis: .vertical)
                    .lineLimit(4...8).font(.body).lineSpacing(4)
                    .accessibilityIdentifier("mealDescription")
                if let data = photoJPEG, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxHeight: 240).frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: 18))
                    Button("移除照片", systemImage: "xmark.circle", action: onRemovePhoto)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Divider()
                HStack(spacing: 12) {
                    Button(action: onCamera) { Label("拍照", systemImage: "camera") }
                        .accessibilityIdentifier("takePhoto")
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        Label("相册选图", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityIdentifier("pickPhoto")
                    if loadingPhoto { ProgressView().accessibilityLabel("正在处理照片") }
                }
                .font(.subheadline).buttonStyle(.bordered).controlSize(.large)
            }
            .contentCard()

            VStack(alignment: .leading, spacing: 12) {
                Text("这些说法都可以").font(.subheadline.weight(.semibold))
                ForEach(["这盒牛奶喝了半盒，按营养表计算", "一小碗熟米饭，一碗青菜和牛肉", "大碗牛肉粉，面吃完了，汤没有喝"], id: \.self) { example in
                    Button { text = example } label: {
                        HStack {
                            Text(example).font(.subheadline).foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(Theme.accent)
                        }
                        .padding(.vertical, 5).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentCard()

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield").foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 8) {
                    Text("点击分析后，文字和压缩后的照片会发送给 DeepSeek，按你的 API 账户计费。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("配置 DeepSeek", action: onSettings).font(.caption.weight(.medium))
                }
            }
            .padding(.horizontal, 6)
        }
    }
}
