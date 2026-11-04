import SwiftUI
import PhotosUI
import NutritionCore

struct ProfileEditorView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(\.dismiss) private var dismiss
    // Keep the opening snapshot stable when a background HealthKit refresh updates the parent.
    @State private var originalProfile: HealthProfile
    @State private var initialWeightText: String
    @State private var initialHeightText: String
    @State private var heightDate: Date?
    @State private var heightFromHealth: Bool
    @State private var nickname: String
    @State private var avatarJPEG: Data?
    @State private var heightText: String
    @State private var weightText: String
    @State private var targetText: String
    @State private var photo: PhotosPickerItem?
    @State private var processingPhoto = false
    @State private var errorMessage: String?

    init(profile: HealthProfile, effectiveHeight: Double?, weight: WeightRecord?, healthHeightDate: Date? = nil) {
        _originalProfile = State(initialValue: profile)
        let height = HealthMeasurementInput.format(effectiveHeight)
        let weight = HealthMeasurementInput.format(weight?.kilograms)
        _initialHeightText = State(initialValue: height)
        _initialWeightText = State(initialValue: weight)
        _heightFromHealth = State(initialValue: profile.heightCM == nil && effectiveHeight != nil)
        _heightDate = State(initialValue: profile.heightCM == nil ? healthHeightDate : profile.heightUpdatedAt)
        _nickname = State(initialValue: profile.nickname)
        _avatarJPEG = State(initialValue: profile.avatarJPEG)
        _heightText = State(initialValue: height)
        _weightText = State(initialValue: weight)
        _targetText = State(initialValue: HealthMeasurementInput.format(profile.targetWeightKG))
    }

    private var bmi: Double? {
        HealthProfile(heightCM: try? HealthMeasurementInput.parse(heightText))
            .bmi(weightKG: try? HealthMeasurementInput.parse(weightText))
    }

    var body: some View {
        let avatar = avatarJPEG
        let isProcessingPhoto = processingPhoto
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    BrandSection("个人信息", symbol: "person.crop.circle") {
                        PhotosPicker(selection: $photo, matching: .images) {
                            HStack(spacing: 18) {
                                ProfileAvatar(data: avatar, size: 78)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(isProcessingPhoto ? "正在处理…" : "更换头像").font(.headline)
                                    Text("给蛙的搭子换个新形象").font(.caption).foregroundStyle(Theme.mutedInk)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }
                        }.buttonStyle(.plain).disabled(processingPhoto).accessibilityIdentifier("chooseAvatar")
                        if avatarJPEG != nil {
                            Button("移除头像", role: .destructive) { avatarJPEG = nil; photo = nil }
                        }
                        Divider()
                        TextField("昵称", text: $nickname).textContentType(.nickname).accessibilityIdentifier("profileNickname")
                    }
                    BrandSection("身体数据", symbol: "figure.stand") {
                        numberField("身高", value: $heightText, unit: "厘米", identifier: "profileHeight")
                        Divider()
                        numberField("当前体重", value: $weightText, unit: "公斤", identifier: "profileWeight")
                        HStack {
                            Text("自动计算 BMI").font(.caption)
                            Spacer()
                            Text(bmi.map { Theme.number($0, decimals: 1) } ?? "待完善")
                                .font(.title2.bold()).monospacedDigit()
                        }.padding(14).background(Theme.softYellow, in: .rect(cornerRadius: 16))
                        Text("BMI = 体重（公斤）÷ 身高（米）的平方。更改当前体重后，保存时会新增测量记录。留空保留已有体重历史。")
                            .font(.caption).foregroundStyle(Theme.mutedInk)
                        if !initialHeightText.isEmpty {
                            Text("原身高来自\(heightFromHealth ? " Apple 健康" : "个人资料")\(heightDate.map { " · " + $0.formatted(.dateTime.year().month().day()) } ?? " · 未记录日期")")
                                .font(.caption2).foregroundStyle(Theme.mutedInk)
                        }
                    }
                    BrandSection("我的目标", symbol: "flag.fill") {
                        numberField("目标体重", value: $targetText, unit: "公斤", identifier: "profileTarget")
                        Text("目标体重可选填，按自己的计划设置。")
                            .font(.caption).foregroundStyle(Theme.mutedInk)
                    }
                    if let errorMessage { ErrorNotice(message: errorMessage).contentCard() }
                }.padding(20)
            }
            .background(Theme.background).scrollDismissesKeyboard(.interactively)
            .navigationTitle("编辑个人资料").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save).disabled(processingPhoto || diary.loadError != nil)
                        .accessibilityIdentifier("saveProfile")
                }
            }
            .task(id: photo) { await loadAvatar() }
        }
    }

    private func numberField(_ title: String, value: Binding<String>, unit: String, identifier: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("选填", text: value)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .frame(maxWidth: 130).accessibilityLabel(title).accessibilityIdentifier(identifier)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func loadAvatar() async {
        guard let photo else { return }
        processingPhoto = true
        defer { processingPhoto = false }
        do {
            guard let data = try await photo.loadTransferable(type: Data.self) else {
                throw DiaryError.invalidInput("这张照片暂时无法读取，请重新选择。")
            }
            let jpeg = try await Task.detached { try PhotoInput.prepareJPEG(data, maxPixelSize: 384) }.value
            guard !Task.isCancelled else { return }
            avatarJPEG = jpeg
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            let height = try HealthMeasurementInput.parse(heightText)
            let weight = try HealthMeasurementInput.parse(weightText)
            let target = try HealthMeasurementInput.parse(targetText)
            // Keep an imported height as a live HealthKit value until the user edits it.
            let heightChanged = height != (try HealthMeasurementInput.parse(initialHeightText))
            let savedHeight = heightChanged ? height : originalProfile.heightCM
            let profile = HealthProfile(nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
                avatarJPEG: avatarJPEG, heightCM: savedHeight, targetWeightKG: target,
                heightUpdatedAt: heightChanged ? (height == nil ? nil : .now) : originalProfile.heightUpdatedAt)
            let newWeight = weight == (try HealthMeasurementInput.parse(initialWeightText)) ? nil : weight
            try diary.saveProfile(profile, weightKG: newWeight)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

}

struct ProfileAvatar: View {
    let data: Data?
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image("MilkFrogPortrait").resizable().scaledToFill()
                    .background(Theme.accent)
            }
        }
        .frame(width: size, height: size).clipShape(.circle)
        .accessibilityHidden(true)
    }
}
