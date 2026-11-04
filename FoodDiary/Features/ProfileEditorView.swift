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
            Form {
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $photo, matching: .images) {
                            VStack(spacing: 12) {
                                ProfileAvatar(data: avatar, size: 90)
                                Text(isProcessingPhoto ? "正在处理…" : "更换头像").font(.subheadline)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(processingPhoto)
                        .accessibilityIdentifier("chooseAvatar")
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    if avatarJPEG != nil {
                        Button("移除头像", role: .destructive) { avatarJPEG = nil; photo = nil }
                    }
                    TextField("昵称", text: $nickname)
                        .textContentType(.nickname)
                        .accessibilityIdentifier("profileNickname")
                } header: { Text("个人信息") }

                Section {
                    numberField("身高", value: $heightText, unit: "厘米", identifier: "profileHeight")
                    numberField("当前体重", value: $weightText, unit: "公斤", identifier: "profileWeight")
                    LabeledContent("BMI", value: bmi.map { Theme.number($0, decimals: 1) } ?? "待完善")
                } header: { Text("身体数据") } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BMI = 体重（公斤）÷ 身高（米）的平方。更改当前体重后，保存时会新增一条测量记录。留空保留已有体重历史。")
                        if !initialHeightText.isEmpty {
                            Text("原身高来自\(heightFromHealth ? " Apple 健康" : "个人资料")\(heightDate.map { " · " + $0.formatted(.dateTime.year().month().day()) } ?? " · 未记录日期")")
                        }
                    }
                }

                Section {
                    numberField("目标体重", value: $targetText, unit: "公斤", identifier: "profileTarget")
                } header: { Text("我的目标") } footer: {
                    Text("目标体重可选填，按自己的计划设置。个人资料保存在这台 iPhone 中。")
                }
                if let errorMessage { Section { ErrorNotice(message: errorMessage) } }
            }
            .scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("编辑个人资料")
            .navigationBarTitleDisplayMode(.inline)
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
