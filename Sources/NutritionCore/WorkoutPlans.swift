import Foundation

public struct PlanExercise: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var sets: Int
    public var reps: Int
    public var weightKG: Double?

    public init(id: UUID = UUID(), name: String, sets: Int = 3, reps: Int = 10, weightKG: Double? = nil) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.weightKG = weightKG
    }

    public func validate() throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40 else { throw DiaryError.invalidInput("动作名称需要 1–40 个字。") }
        guard (1...20).contains(sets) else { throw DiaryError.invalidInput("每个动作的组数需要在 1–20 之间。") }
        guard (1...500).contains(reps) else { throw DiaryError.invalidInput("次数需要在 1–500 之间。") }
        if let weightKG, !(0...500).contains(weightKG) {
            throw DiaryError.invalidInput("重量需要在 0–500 kg 之间。")
        }
    }
}

/// 一次训练的计划：只描述「打算练什么」，开始练时再变成 `WorkoutRecord`。
public struct WorkoutPlan: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: WorkoutKind
    public var plannedMinutes: Int
    public var exercises: [PlanExercise]
    public var cardio: CardioDetail?
    public var createdAt: Date
    public var lastUsedAt: Date
    public var useCount: Int

    public init(id: UUID = UUID(), name: String, kind: WorkoutKind = .strength,
                plannedMinutes: Int = 45, exercises: [PlanExercise] = [],
                cardio: CardioDetail? = nil, createdAt: Date = .now,
                lastUsedAt: Date = .now, useCount: Int = 0) {
        self.id = id
        self.name = name
        self.kind = kind
        self.plannedMinutes = plannedMinutes
        self.exercises = exercises
        self.cardio = cardio
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }

    public init(workout: WorkoutRecord, name: String, now: Date = .now) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(name: trimmed.isEmpty ? workout.displayTitle : trimmed,
                  kind: workout.kind,
                  plannedMinutes: workout.durationMinutes,
                  exercises: workout.exercises.map { exercise in
                      PlanExercise(name: exercise.name,
                                   sets: max(1, exercise.sets.count),
                                   reps: exercise.sets.first?.reps ?? 10,
                                   weightKG: exercise.sets.first?.weightKG)
                  },
                  cardio: workout.cardio,
                  createdAt: now, lastUsedAt: now)
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.title : trimmed
    }

    public var summary: String {
        var parts = ["\(plannedMinutes) 分钟"]
        if kind == .strength {
            parts.append("\(exercises.count) 个动作")
            let totalSets = exercises.reduce(0) { $0 + $1.sets }
            if totalSets > 0 { parts.append("\(totalSets) 组") }
        } else if let cardio {
            parts.append(cardio.activity.title)
            if let distance = cardio.distanceMeters {
                parts.append(String(format: "%.1f km", distance / 1000))
            }
        }
        return parts.joined(separator: " · ")
    }

    public func validate() throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { throw DiaryError.invalidInput("计划名称需要 1–40 个字。") }
        guard (1...600).contains(plannedMinutes) else { throw DiaryError.invalidInput("计划时长需要在 1–600 分钟之间。") }
        if kind == .strength {
            guard (1...30).contains(exercises.count) else {
                throw DiaryError.invalidInput("力量计划需要 1–30 个动作。")
            }
            try exercises.forEach { try $0.validate() }
        } else {
            guard let cardio else { throw DiaryError.invalidInput("有氧计划需要选择项目。") }
            try cardio.validate()
        }
    }

    /// 按计划生成一条今天的训练，动作里的组数会展开成实际组。
    public func makeWorkout(on date: Date = .now, calendar: Calendar = .current) -> WorkoutRecord {
        let exerciseRecords = exercises.map { exercise in
            StrengthExercise(name: exercise.name,
                             sets: (0..<exercise.sets).map { _ in
                                 StrengthSet(reps: exercise.reps, weightKG: exercise.weightKG)
                             })
        }
        return WorkoutRecord(date: date, kind: kind, title: name,
                             durationMinutes: plannedMinutes,
                             exercises: exerciseRecords, cardio: cardio)
    }

    public mutating func markUsed(now: Date = .now) {
        lastUsedAt = now
        useCount += 1
    }
}
