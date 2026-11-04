import Foundation

public enum WorkoutKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case strength, cardio

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .strength: "力量"
        case .cardio: "有氧"
        }
    }

    public var symbol: String {
        switch self {
        case .strength: "dumbbell"
        case .cardio: "figure.run"
        }
    }
}

public enum CardioActivity: String, Codable, CaseIterable, Sendable, Identifiable {
    case walk, run, cycle, swim, row, hike, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .walk: "快走"
        case .run: "跑步"
        case .cycle: "骑行"
        case .swim: "游泳"
        case .row: "划船"
        case .hike: "爬山"
        case .other: "其他"
        }
    }
}

public struct StrengthSet: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var reps: Int
    public var weightKG: Double?

    public init(id: UUID = UUID(), reps: Int, weightKG: Double? = nil) {
        self.id = id
        self.reps = reps
        self.weightKG = weightKG
    }

    public var volume: Double { Double(reps) * (weightKG ?? 0) }

    public func validate() throws {
        guard (1...500).contains(reps) else { throw DiaryError.invalidInput("次数需要在 1–500 之间。") }
        if let weightKG, !(0...500).contains(weightKG) {
            throw DiaryError.invalidInput("重量需要在 0–500 kg 之间。")
        }
    }
}

public struct StrengthExercise: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var sets: [StrengthSet]

    public init(id: UUID = UUID(), name: String, sets: [StrengthSet] = []) {
        self.id = id
        self.name = name
        self.sets = sets
    }

    public var volume: Double { sets.reduce(0) { $0 + $1.volume } }
    public var totalReps: Int { sets.reduce(0) { $0 + $1.reps } }

    public func validate() throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40 else {
            throw DiaryError.invalidInput("动作名称需要 1–40 个字。")
        }
        guard (1...20).contains(sets.count) else {
            throw DiaryError.invalidInput("每个动作的组数需要在 1–20 之间。")
        }
        try sets.forEach { try $0.validate() }
    }
}

public struct CardioDetail: Codable, Equatable, Sendable {
    public var activity: CardioActivity
    public var distanceMeters: Double?
    public var averageHeartRate: Int?

    public init(activity: CardioActivity = .run, distanceMeters: Double? = nil, averageHeartRate: Int? = nil) {
        self.activity = activity
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
    }

    public func validate() throws {
        if let distanceMeters, !(0...200_000).contains(distanceMeters) {
            throw DiaryError.invalidInput("距离需要在 0–200 公里之间。")
        }
        if let averageHeartRate, !(30...240).contains(averageHeartRate) {
            throw DiaryError.invalidInput("平均心率需要在 30–240 之间。")
        }
    }
}

public struct WorkoutRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var kind: WorkoutKind
    public var title: String
    public var durationMinutes: Int
    public var perceivedEffort: Int?
    public var caloriesBurned: Double?
    public var notes: String
    public var exercises: [StrengthExercise]
    public var cardio: CardioDetail?

    public init(id: UUID = UUID(), date: Date = .now, kind: WorkoutKind = .strength,
                title: String = "", durationMinutes: Int = 45, perceivedEffort: Int? = nil,
                caloriesBurned: Double? = nil, notes: String = "",
                exercises: [StrengthExercise] = [], cardio: CardioDetail? = nil) {
        self.id = id
        self.date = date
        self.kind = kind
        self.title = title
        self.durationMinutes = durationMinutes
        self.perceivedEffort = perceivedEffort
        self.caloriesBurned = caloriesBurned
        self.notes = notes
        self.exercises = exercises
        self.cardio = cardio
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let cardio { return cardio.activity.title }
        return kind.title
    }

    public var volume: Double { exercises.reduce(0) { $0 + $1.volume } }
    public var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }

    public func validate() throws {
        guard date.timeIntervalSinceReferenceDate.isFinite else { throw DiaryError.invalidInput("训练时间不合法。") }
        guard (1...600).contains(durationMinutes) else {
            throw DiaryError.invalidInput("训练时长需要在 1–600 分钟之间。")
        }
        guard title.count <= 40 else { throw DiaryError.invalidInput("训练名称最多 40 个字。") }
        guard notes.count <= 500 else { throw DiaryError.invalidInput("备注最多 500 个字。") }
        if let perceivedEffort, !(1...10).contains(perceivedEffort) {
            throw DiaryError.invalidInput("体感强度需要在 1–10 之间。")
        }
        if let caloriesBurned, !(0...5000).contains(caloriesBurned) {
            throw DiaryError.invalidInput("消耗热量需要在 0–5000 之间。")
        }
        if kind == .strength {
            guard (1...30).contains(exercises.count) else {
                throw DiaryError.invalidInput("力量训练需要 1–30 个动作。")
            }
            try exercises.forEach { try $0.validate() }
        } else {
            guard let cardio else { throw DiaryError.invalidInput("有氧训练需要选择项目。") }
            try cardio.validate()
        }
    }
}

public struct WorkoutStats: Sendable, Equatable {
    public var sessions: Int = 0
    public var minutes: Int = 0
    public var strengthVolume: Double = 0
    public var cardioMeters: Double = 0
    public var passedCalories: Double = 0
    public var lastDate: Date?

    public init() {}
}

public enum WorkoutSummary {
    public static func stats(for document: DiaryDocument, since: Date? = nil,
                             calendar: Calendar = .current) -> WorkoutStats {
        var stats = WorkoutStats()
        for workout in document.workouts where since == nil || workout.date >= since! {
            stats.sessions += 1
            stats.minutes += workout.durationMinutes
            stats.strengthVolume += workout.volume
            stats.cardioMeters += workout.cardio?.distanceMeters ?? 0
            stats.passedCalories += workout.caloriesBurned ?? 0
            if stats.lastDate == nil || workout.date > stats.lastDate! { stats.lastDate = workout.date }
        }
        return stats
    }
}
