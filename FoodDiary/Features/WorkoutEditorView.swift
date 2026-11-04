import SwiftUI
import NutritionCore

struct WorkoutEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let workout: WorkoutRecord?
    let onSave: (WorkoutRecord) -> Void

    @State private var date: Date
    @State private var kind: WorkoutKind
    @State private var title: String
    @State private var durationText: String
    @State private var effort: Int
    @State private var chargesEffort: Bool
    @State private var caloriesText: String
    @State private var activity: CardioActivity
    @State private var distanceText: String
    @State private var heartRateText: String
    @State private var exercises: [StrengthExercise]
    @State private var errorMessage: String?

    init(workout: WorkoutRecord?, onSave: @escaping (WorkoutRecord) -> Void) {
        self.workout = workout
        self.onSave = onSave
        _date = State(initialValue: workout?.date ?? .now)
        _kind = State(initialValue: workout?.kind ?? .strength)
        _title = State(initialValue: workout?.title ?? "")
        _durationText = State(initialValue: "\(workout?.durationMinutes ?? 45)")
        _effort = State(initialValue: workout?.perceivedEffort ?? 7)
        _chargesEffort = State(initialValue: workout?.perceivedEffort != nil)
        _caloriesText = State(initialValue: workout?.caloriesBurned.map { String(Int($0)) } ?? "")
        _activity = State(initialValue: workout?.cardio?.activity ?? .run)
        _distanceText = State(initialValue: workout?.cardio?.distanceMeters.map { String(format: "%.2f", $0 / 1000) } ?? "")
        _heartRateText = State(initialValue: workout?.cardio?.averageHeartRate.map(String.init) ?? "")
        _exercises = State(initialValue: workout?.exercises ?? [StrengthExercise(name: "", sets: [StrengthSet(reps: 10)])])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $kind) {
                        ForEach(WorkoutKind.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    DatePicker("时间", selection: $date, displayedComponents: [.date])
                    TextField(kind == .strength ? "训练名称（可选，如「推日」）" : "名称（可选）", text: $title)
                    HStack {
                        Text("时长")
                        Spacer()
                        TextField("45", text: $durationText).keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing).frame(width: 60)
                        Text("分钟").foregroundStyle(Theme.mutedInk)
                    }
                }

                if kind == .strength {
                    Section("动作") {
                        ForEach($exercises) { $exercise in
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("动作名称", text: $exercise.name)
                                HStack(spacing: 8) {
                                    Text("\(exercise.sets.count) 组 ×").font(.caption).foregroundStyle(Theme.mutedInk)
                                    if let first = exercise.sets.first {
                                        Text("\(first.reps) 次").font(.caption)
                                    }
                                    Spacer()
                                    Button("加一组") { addSet(to: $exercise) }.font(.caption)
                                }
                                ForEach($exercise.sets) { $set in
                                    HStack(spacing: 8) {
                                        TextField("次数", text: Binding(
                                            get: { "\(set.reps)" },
                                            set: { set.reps = Int($0) ?? set.reps }
                                        )).keyboardType(.numberPad).frame(width: 60)
                                        Text("次").font(.caption)
                                        TextField("重量", text: Binding(
                                            get: { set.weightKG.map { String(format: "%g", $0) } ?? "" },
                                            set: { set.weightKG = Double($0.replacingOccurrences(of: ",", with: ".")) }
                                        )).keyboardType(.decimalPad).frame(width: 70)
                                        Text("kg").font(.caption)
                                        Spacer()
                                    }
                                }
                            }
                            .swipeActions {
                                Button("删除动作", role: .destructive) { exercises.removeAll { $0.id == exercise.id } }
                            }
                        }
                        Button("添加动作") {
                            exercises.append(StrengthExercise(name: "", sets: [StrengthSet(reps: 10)]))
                        }
                    }
                } else {
                    Section("有氧") {
                        Picker("项目", selection: $activity) {
                            ForEach(CardioActivity.allCases) { Text($0.title).tag($0) }
                        }
                        HStack {
                            Text("距离")
                            Spacer()
                            TextField("5.0", text: $distanceText).keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing).frame(width: 70)
                            Text("km").foregroundStyle(Theme.mutedInk)
                        }
                        HStack {
                            Text("平均心率")
                            Spacer()
                            TextField("148", text: $heartRateText).keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing).frame(width: 70)
                            Text("bpm").foregroundStyle(Theme.mutedInk)
                        }
                    }
                }

                Section("感受") {
                    Toggle("记录体感强度", isOn: $chargesEffort)
                    if chargesEffort {
                        Stepper("体感 \(effort) / 10", value: $effort, in: 1...10)
                    }
                    HStack {
                        Text("消耗")
                        Spacer()
                        TextField("可选", text: $caloriesText).keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing).frame(width: 70)
                        Text("kcal").foregroundStyle(Theme.mutedInk)
                    }
                }
            }
            .navigationTitle(workout == nil ? "记一次训练" : "编辑训练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.accessibilityIdentifier("saveWorkout")
                }
            }
            .alert("没有保存", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func addSet(to exercise: Binding<StrengthExercise>) {
        let last = exercise.wrappedValue.sets.last
        exercise.wrappedValue.sets.append(StrengthSet(reps: last?.reps ?? 10, weightKG: last?.weightKG))
    }

    private func save() {
        var record = workout ?? WorkoutRecord()
        record.date = date
        record.kind = kind
        record.title = title
        record.durationMinutes = Int(durationText) ?? 45
        record.perceivedEffort = chargesEffort ? effort : nil
        record.caloriesBurned = caloriesText.isEmpty ? nil : Double(caloriesText)
        if kind == .strength {
            record.exercises = exercises.filter {
                !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            record.cardio = nil
        } else {
            record.exercises = []
            record.cardio = CardioDetail(activity: activity,
                                         distanceMeters: distanceText.isEmpty ? nil
                                            : Double(distanceText.replacingOccurrences(of: ",", with: ".")).map { $0 * 1000 },
                                         averageHeartRate: Int(heartRateText))
        }
        do {
            try record.validate()
            onSave(record)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
