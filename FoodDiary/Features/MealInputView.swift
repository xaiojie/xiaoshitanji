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
    let photoJPEG: Data?
    let loadingPhoto: Bool
    let onCamera: () -> Void
    let onRemovePhoto: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            BrandSegments(options: FoodAnalysisMode.allCases.map { ($0, $0.title) }, selection: $mode)
            if let photoJPEG {
                ScanPhotoPreview(data: photoJPEG, height: 290)
                Button("移除照片", systemImage: "xmark.circle", action: onRemovePhoto)
                    .font(.caption).foregroundStyle(Theme.mutedInk)
            } else {
                VStack(spacing: 15) {
                    Image(systemName: "viewfinder").font(.system(size: 54, weight: .light)).foregroundStyle(Theme.accent)
                    Text(mode == .label ? "对准营养成分表" : "拍下碗里的这一餐")
                        .font(.title3.bold()).foregroundStyle(Theme.surface)
                    Text(mode == .label ? "拍清单位、每份营养值和净含量" : "AI 根据食物、碗型和装满程度估算")
                        .font(.caption).foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity).frame(height: 220)
                .background(Theme.darkGradient, in: .rect(cornerRadius: 26))
            }

            HStack(spacing: 12) {
                Button(action: onCamera) {
                    Label(photoJPEG == nil ? "拍照" : "重新拍照", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity, minHeight: 42)
                }.yellowAction().accessibilityIdentifier("takePhoto")
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Label("相册选图", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 42)
                }.buttonStyle(.glass).accessibilityIdentifier("pickPhoto")
            }.font(.subheadline.bold())
            if loadingPhoto { ProgressView("正在处理照片…").font(.caption) }

            VStack(alignment: .leading, spacing: 13) {
                Label("吃了多少？说一句就好", systemImage: "text.bubble").font(.headline)
                TextField("比如：牛奶喝了半盒，或一碗牛肉粉只吃了面", text: $text, axis: .vertical)
                    .lineLimit(2...5).font(.subheadline).lineSpacing(4)
                    .accessibilityIdentifier("mealDescription")
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

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield").foregroundStyle(Theme.olive)
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
