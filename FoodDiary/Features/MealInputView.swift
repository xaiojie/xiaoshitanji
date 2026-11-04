import SwiftUI
import PhotosUI
import NutritionCore

struct MealMetadataView: View {
    @Binding var kind: MealKind
    @Binding var date: Date

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
            DatePicker("用餐时间", selection: $date, in: ...Date.now)
                .font(.subheadline)
        }
        .contentCard()
    }
}

struct MealInputView: View {
    @Binding var text: String
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
                Text("拍张照，或像聊天一样描述。份量、热量和营养交给 AI 来估算。")
                    .font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
            }
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 18) {
                TextField("比如：一碗牛肉粉，一杯无糖豆浆，粉只吃了一半", text: $text, axis: .vertical)
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
                    Button(action: onCamera) { Label("拍摄食物", systemImage: "camera") }
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
                ForEach(["早餐两个包子，一杯豆浆", "午饭一份外卖，米饭剩了一半", "刚喝了一杯中杯拿铁，少糖"], id: \.self) { example in
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
