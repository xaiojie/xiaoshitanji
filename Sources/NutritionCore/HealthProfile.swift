import Foundation

public struct HealthProfile: Codable, Equatable, Sendable {
    public var nickname: String
    public var avatarJPEG: Data?
    public var heightCM: Double?
    public var heightUpdatedAt: Date?
    public var targetWeightKG: Double?

    public init(nickname: String = "", avatarJPEG: Data? = nil, heightCM: Double? = nil,
                targetWeightKG: Double? = nil, heightUpdatedAt: Date? = nil) {
        self.nickname = nickname
        self.avatarJPEG = avatarJPEG
        self.heightCM = heightCM
        self.heightUpdatedAt = heightUpdatedAt
        self.targetWeightKG = targetWeightKG
    }

    public func bmi(weightKG: Double?) -> Double? {
        guard let heightCM, (50...250).contains(heightCM),
              let weightKG, (1...500).contains(weightKG) else { return nil }
        let heightMeters = heightCM / 100
        return weightKG / (heightMeters * heightMeters)
    }

    public func validate() throws {
        guard nickname.count <= 40 else { throw DiaryError.invalidInput("昵称请控制在 40 个字以内。") }
        guard (avatarJPEG?.count ?? 0) <= 2_000_000 else { throw DiaryError.invalidInput("头像较大，请重新选择。") }
        if let heightCM, !(50...250).contains(heightCM) {
            throw DiaryError.invalidInput("请填写 50 至 250 厘米范围内的身高。")
        }
        if let targetWeightKG, !(1...500).contains(targetWeightKG) {
            throw DiaryError.invalidInput("请填写有效的目标体重，单位为公斤。")
        }
        if let heightUpdatedAt, !heightUpdatedAt.timeIntervalSinceReferenceDate.isFinite {
            throw DiaryError.invalidInput("身高记录的时间无效，请重新填写身高。")
        }
    }
}

public enum WeightSource: String, Codable, Sendable {
    case manual, appleHealth
    public var title: String { self == .manual ? "手动记录" : "Apple 健康" }
}

public struct WeightRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var kilograms: Double
    public var source: WeightSource

    public init(id: UUID = UUID(), date: Date = .now, kilograms: Double, source: WeightSource = .manual) {
        self.id = id
        self.date = date
        self.kilograms = kilograms
        self.source = source
    }

    public func validate() throws {
        guard date.timeIntervalSinceReferenceDate.isFinite, (1...500).contains(kilograms) else {
            throw DiaryError.invalidInput("请填写 1 至 500 公斤范围内的体重和有效的测量时间。")
        }
    }

    public static func latest(in records: [WeightRecord]) -> WeightRecord? {
        records.max {
            if $0.date == $1.date { return $0.source == .appleHealth && $1.source == .manual }
            return $0.date < $1.date
        }
    }
}

public struct HealthActivityDay: Identifiable, Equatable, Sendable {
    public var date: Date
    public var steps: Double?
    public var activeCalories: Double?
    public var exerciseMinutes: Double?
    public var distanceMeters: Double?
    public var sleepHours: Double?
    public var averageHeartRate: Double?
    public var restingHeartRate: Double?
    public var heartRateVariabilityMS: Double?
    public var vo2Max: Double?
    public var headphoneAudioMinutes: Double?
    public var workoutSessions: Double?
    public var workoutMinutes: Double?
    public var workoutCalories: Double?
    public var id: Date { date }

    public init(date: Date, steps: Double? = nil, activeCalories: Double? = nil,
                exerciseMinutes: Double? = nil, distanceMeters: Double? = nil,
                sleepHours: Double? = nil, averageHeartRate: Double? = nil,
                restingHeartRate: Double? = nil, heartRateVariabilityMS: Double? = nil,
                vo2Max: Double? = nil, headphoneAudioMinutes: Double? = nil,
                workoutSessions: Double? = nil, workoutMinutes: Double? = nil,
                workoutCalories: Double? = nil) {
        self.date = date
        self.steps = steps
        self.activeCalories = activeCalories
        self.exerciseMinutes = exerciseMinutes
        self.distanceMeters = distanceMeters
        self.sleepHours = sleepHours
        self.averageHeartRate = averageHeartRate
        self.restingHeartRate = restingHeartRate
        self.heartRateVariabilityMS = heartRateVariabilityMS
        self.vo2Max = vo2Max
        self.headphoneAudioMinutes = headphoneAudioMinutes
        self.workoutSessions = workoutSessions
        self.workoutMinutes = workoutMinutes
        self.workoutCalories = workoutCalories
    }
}
