import SwiftUI
import NutritionCore

struct WorkoutLogView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(\.dismiss) private var dismiss
    @State private var editing: WorkoutRecord?
    @State private var adding = false
    @State private var errorMessage: String?

    private var stats: WorkoutStats { WorkoutSummary.stats(for: diary.document) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.title2).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(stats.sessions) 次 · \(stats.minutes) 分钟").font(.headline)
                            Text(volumeText).font(.caption).foregroundStyle(Theme.mutedInk)
                        }
                        Spacer()
                    }
                    .contentCard()
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }

                if diary.document.workouts.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("还没有训练记录").font(.headline)
                            Text("力量记动作、组数、重量；有氧记时长、距离和心率。")
                                .font(.subheadline).foregroundStyle(Theme.mutedInk)
                        }.padding(.vertical, 8)
                    }
                } else {
                    ForEach(grouped, id: \.0) { day, workouts in
                        Section(day.formatted(date: .abbreviated, time: .omitted)) {
                            ForEach(workouts) { workout in
                                Button { editing = workout } label: { row(workout) }
                                    .buttonStyle(.plain)
                                    .swipeActions {
                                        Button("删除", role: .destructive) { delete(workout) }
                                    }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("训练").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityIdentifier("addWorkout")
                }
            }
            .sheet(isPresented: $adding) {
                WorkoutEditorView(workout: nil) { save($0) }
            }
            .sheet(item: $editing) { workout in
                WorkoutEditorView(workout: workout) { save($0) }
            }
            .alert("没有保存", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var volumeText: String {
        var parts: [String] = []
        if stats.strengthVolume > 0 { parts.append("力量容量 \(Theme.number(stats.strengthVolume)) kg") }
        if stats.cardioMeters > 0 { parts.append(String(format: "有氧 %.1f km", stats.cardioMeters / 1000)) }
        return parts.isEmpty ? "记一次，趋势里就能看到。" : parts.joined(separator: " · ")
    }

    private var grouped: [(Date, [WorkoutRecord])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: diary.document.workouts) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!.sorted { $0.date > $1.date }) }
    }

    private func row(_ workout: WorkoutRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: workout.kind.symbol)
                .frame(width: 30).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.displayTitle).font(.subheadline.weight(.semibold))
                Text(detail(workout)).font(.caption).foregroundStyle(Theme.mutedInk)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.mutedInk)
        }
        .foregroundStyle(Theme.ink)
        .padding(.vertical, 2)
    }

    private func detail(_ workout: WorkoutRecord) -> String {
        var parts = ["\(workout.durationMinutes) 分钟"]
        if workout.kind == .strength {
            parts.append("\(workout.exercises.count) 个动作 · \(workout.totalSets) 组")
        } else if let cardio = workout.cardio {
            if let distance = cardio.distanceMeters { parts.append(String(format: "%.1f km", distance / 1000)) }
            if let hr = cardio.averageHeartRate { parts.append("\(hr) bpm") }
        }
        if let effort = workout.perceivedEffort { parts.append("体感 \(effort)") }
        return parts.joined(separator: " · ")
    }

    private func save(_ workout: WorkoutRecord) {
        do {
            try diary.saveWorkout(workout)
            adding = false
            editing = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ workout: WorkoutRecord) {
        try? diary.deleteWorkout(workout)
    }
}
