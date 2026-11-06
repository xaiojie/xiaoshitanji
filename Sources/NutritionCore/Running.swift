import Foundation

public enum RunMovement: String, Codable, Sendable {
    case stationary, moving, unknown
}

public struct RunLocation: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var timestamp: Date
    public var horizontalAccuracy: Double
    public var speed: Double?
    public var speedAccuracy: Double?
    public var movement: RunMovement?

    public init(latitude: Double, longitude: Double, timestamp: Date, horizontalAccuracy: Double,
                speed: Double? = nil, speedAccuracy: Double? = nil, movement: RunMovement? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.speedAccuracy = speedAccuracy
        self.movement = movement
    }

    public var hasStationarySpeed: Bool {
        guard let speed, let speedAccuracy, speed.isFinite, speedAccuracy.isFinite,
              (0...1.5).contains(speedAccuracy) else { return false }
        return (0..<0.5).contains(speed)
    }

    public var hasMovingSpeed: Bool {
        guard let speed, let speedAccuracy, speed.isFinite, speedAccuracy.isFinite,
              (0...1).contains(speedAccuracy) else { return false }
        return speed >= 0.7 && speed - speedAccuracy >= 0.3
    }

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude)
            && (-180...180).contains(longitude) && horizontalAccuracy.isFinite
            && (0...35).contains(horizontalAccuracy) && timestamp.timeIntervalSince1970.isFinite
    }

    public func distance(to other: RunLocation) -> Double {
        let radians = Double.pi / 180
        let latitudeDelta = (other.latitude - latitude) * radians
        let longitudeDelta = (other.longitude - longitude) * radians
        let a = pow(sin(latitudeDelta / 2), 2)
            + cos(latitude * radians) * cos(other.latitude * radians) * pow(sin(longitudeDelta / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, a))))
    }
}

public struct RunTrackPoint: Codable, Equatable, Sendable {
    public let location: RunLocation
    public let activeSeconds: Double
    public let distanceMeters: Double
    public let segment: Int
}

public struct RunInterval: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date?
}

public struct RunSplit: Equatable, Sendable, Identifiable {
    public let kilometer: Int
    public let distanceMeters: Double
    public let seconds: Double
    public var id: Int { kilometer }
    public var pace: Double { seconds / distanceMeters * 1000 }
}

public struct RunSession: Codable, Equatable, Sendable, Identifiable {
    public enum State: String, Codable, Sendable { case running, paused, finished }

    public let id: UUID
    public let startedAt: Date
    public let targetMeters: Double?
    public let usesGPS: Bool
    public private(set) var state: State = .running
    public private(set) var intervals: [RunInterval]
    public private(set) var points: [RunTrackPoint] = []
    public private(set) var distanceMeters: Double = 0
    public private(set) var goalReached = false
    public private(set) var lastCheckpoint: Date
    public private(set) var endedAt: Date?
    private var segment = 0
    /// 没有速度或运动识别时，用短窗口验证持续位移，避免累加定位噪声。
    private var movementCandidates: [RunLocation]?
    private var movementUnconfirmed: Bool?

    public init(id: UUID = UUID(), startedAt: Date = .now, targetMeters: Double? = nil, usesGPS: Bool = true) {
        self.id = id
        self.startedAt = startedAt
        self.targetMeters = targetMeters
        self.usesGPS = usesGPS
        self.lastCheckpoint = startedAt
        self.intervals = [RunInterval(start: startedAt)]
    }

    public static func targetMeters(from text: String) throws -> Double {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "，", with: ".")
        guard let kilometers = Double(text), kilometers.isFinite, (0.1...200).contains(kilometers) else {
            throw DiaryError.invalidInput("目标里程请填写 0.1 至 200 公里。")
        }
        return kilometers * 1000
    }

    public func activeSeconds(at date: Date) -> Double {
        intervals.reduce(0) { $0 + max(0, ($1.end ?? date).timeIntervalSince($1.start)) }
    }

    public var averagePace: Double? {
        guard distanceMeters >= 10 else { return nil }
        return activeSeconds(at: endedAt ?? lastCheckpoint) / distanceMeters * 1000
    }

    public func currentPace(at date: Date) -> Double? {
        guard state == .running, movementUnconfirmed != true, let last = points.last, last.segment == segment,
              date.timeIntervalSince(last.location.timestamp) <= 20 else { return nil }
        let recent = points.suffix(30).filter {
            $0.segment == last.segment && last.activeSeconds - $0.activeSeconds <= 30
        }
        guard let first = recent.first, last.distanceMeters - first.distanceMeters >= 10,
              last.activeSeconds > first.activeSeconds else { return nil }
        return (last.activeSeconds - first.activeSeconds) / (last.distanceMeters - first.distanceMeters) * 1000
    }

    public mutating func checkpoint(at date: Date) {
        guard state != .finished else { return }
        lastCheckpoint = max(lastCheckpoint, date)
    }

    public mutating func pause(at date: Date) {
        guard state == .running else { return }
        checkpoint(at: date)
        intervals[intervals.count - 1].end = max(intervals[intervals.count - 1].start, date)
        state = .paused
        breakTrack()
    }

    public mutating func resume(at date: Date) {
        guard state == .paused else { return }
        intervals.append(RunInterval(start: max(lastCheckpoint, date)))
        state = .running
        checkpoint(at: date)
    }

    public mutating func finish(at date: Date) {
        guard state != .finished else { return }
        pause(at: date)
        endedAt = max(lastCheckpoint, date)
        lastCheckpoint = endedAt!
        state = .finished
    }

    /// 重启只能确认到已落盘时刻，进程不在时的移动和时间保持为中断。
    public mutating func recover() {
        if state == .running { pause(at: lastCheckpoint) }
    }

    public mutating func breakTrack() {
        if points.last?.segment == segment { segment += 1 }
        movementCandidates = nil
        movementUnconfirmed = true
    }

    /// 仅在本次首次达到目标时返回 true。
    @discardableResult
    public mutating func ingest(_ location: RunLocation, receivedAt date: Date) -> Bool {
        guard state == .running, let interval = intervals.last,
              location.timestamp >= interval.start, points.count < 100_000,
              location.timestamp.timeIntervalSince(date) <= 5,
              date.timeIntervalSince(location.timestamp) <= 15 else { return false }
        guard location.isValid else { breakTrack(); return false }
        if location.movement == .stationary || location.hasStationarySpeed {
            breakTrack()
            checkpoint(at: location.timestamp)
            return false
        }
        if location.movement == .moving || location.hasMovingSpeed {
            movementCandidates = nil
            movementUnconfirmed = false
            return appendMovingLocation(location)
        }
        return confirmUnclassifiedMovement(location)
    }

    private mutating func confirmUnclassifiedMovement(_ location: RunLocation) -> Bool {
        movementUnconfirmed = true
        var candidates = movementCandidates ?? []
        if candidates.isEmpty, let last = points.last, last.segment == segment,
           location.timestamp.timeIntervalSince(last.location.timestamp) <= 20 {
            candidates.append(last.location)
        }
        if let last = candidates.last {
            let seconds = location.timestamp.timeIntervalSince(last.timestamp)
            guard seconds > 0 else { return false }
            if seconds > 20 || last.distance(to: location) / seconds > 12 {
                breakTrack()
                candidates = []
            }
        }
        candidates.append(location)
        let uncertainty = max(15, (candidates.first?.horizontalAccuracy ?? location.horizontalAccuracy)
                               + location.horizontalAccuracy)
        // 窗口足够跨越当前精度包络，低精度慢走也能积累到有效证据。
        let windowSeconds = max(30, min(120, uncertainty / 0.7 * 1.25))
        candidates = Array(candidates.filter {
            location.timestamp.timeIntervalSince($0.timestamp) <= windowSeconds
        }.suffix(256))
        movementCandidates = candidates
        guard candidates.count >= 3, let first = candidates.first else { return false }
        let seconds = location.timestamp.timeIntervalSince(first.timestamp)
        let displacement = first.distance(to: location)
        let requiredDisplacement = max(15, first.horizontalAccuracy + location.horizontalAccuracy)
        let path = zip(candidates, candidates.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        guard seconds >= 3, displacement >= requiredDisplacement, displacement / seconds >= 0.7,
              path > 0, displacement / path >= 0.75 else { return false }
        var reachedGoal = false
        for candidate in candidates {
            reachedGoal = appendMovingLocation(candidate) || reachedGoal
        }
        // 已确认的运动不能替后续静止抖动提供证据，下一批从新的锚点验证。
        movementCandidates = [location]
        movementUnconfirmed = false
        return reachedGoal
    }

    private mutating func appendMovingLocation(_ location: RunLocation) -> Bool {
        if let last = points.last {
            guard location.timestamp > last.location.timestamp else { return false }
            if last.segment == segment {
                let seconds = location.timestamp.timeIntervalSince(last.location.timestamp)
                let meters = last.location.distance(to: location)
                if seconds > 20 {
                    breakTrack()
                } else if meters / seconds > 12 {
                    breakTrack()
                    return false
                } else {
                    guard meters >= max(3, location.horizontalAccuracy * 0.3) else { return false }
                    distanceMeters += meters
                }
            }
        }
        checkpoint(at: location.timestamp)
        points.append(RunTrackPoint(location: location, activeSeconds: activeSeconds(at: location.timestamp),
                                    distanceMeters: distanceMeters, segment: segment))
        guard let targetMeters, !goalReached, distanceMeters >= targetMeters else { return false }
        goalReached = true
        return true
    }

    public var splits: [RunSplit] {
        guard distanceMeters > 0, points.count > 1 else { return [] }
        var result: [RunSplit] = []
        var boundary = 1000.0
        var previousBoundaryTime = 0.0
        for index in 1..<points.count {
            let before = points[index - 1]
            let after = points[index]
            guard after.distanceMeters > before.distanceMeters else { continue }
            while boundary <= after.distanceMeters + 0.001 {
                let ratio = min(1, (boundary - before.distanceMeters) / (after.distanceMeters - before.distanceMeters))
                let time = before.activeSeconds + ratio * (after.activeSeconds - before.activeSeconds)
                result.append(RunSplit(kilometer: result.count + 1, distanceMeters: 1000,
                                       seconds: max(0, time - previousBoundaryTime)))
                previousBoundaryTime = time
                boundary += 1000
            }
        }
        let remainder = distanceMeters - Double(result.count) * 1000
        if remainder >= 1 {
            result.append(RunSplit(kilometer: result.count + 1, distanceMeters: remainder,
                                   seconds: max(0, activeSeconds(at: endedAt ?? lastCheckpoint) - previousBoundaryTime)))
        }
        return result
    }

    public func estimatedCalories(weightKG: Double?) -> Double? {
        guard let weightKG, weightKG.isFinite, (20...400).contains(weightKG), distanceMeters > 0 else { return nil }
        return 0.9 * weightKG * distanceMeters / 1000
    }

    public func containsActiveTime(_ date: Date) -> Bool {
        intervals.contains { date >= $0.start && date <= ($0.end ?? lastCheckpoint) }
    }

    public func validate() throws {
        guard startedAt.timeIntervalSince1970.isFinite, lastCheckpoint >= startedAt,
              !intervals.isEmpty, intervals.count <= 10_000, points.count <= 100_000,
              distanceMeters.isFinite, (0...1_000_000).contains(distanceMeters),
              targetMeters.map({ $0.isFinite && (100...200_000).contains($0) }) ?? true,
              (0...604_800).contains(activeSeconds(at: lastCheckpoint)),
              intervals.allSatisfy({ $0.start >= startedAt && ($0.end ?? lastCheckpoint) >= $0.start }),
              points.allSatisfy({ $0.location.isValid && $0.activeSeconds.isFinite && $0.distanceMeters.isFinite }) else {
            throw DiaryError.invalidInput("跑步记录格式异常，原文件已保留。")
        }
    }
}

public struct RunHeartRatePoint: Codable, Equatable, Sendable, Identifiable {
    public let date: Date
    public let bpm: Double
    public let source: String
    public var id: String { "\(source)-\(date.timeIntervalSince1970)" }

    public init(date: Date, bpm: Double, source: String) {
        self.date = date
        self.bpm = bpm
        self.source = source
    }
}

public struct RunHeartRateSummary: Equatable, Sendable {
    public let points: [RunHeartRatePoint]
    public let source: String
    public var average: Double { points.reduce(0) { $0 + $1.bpm } / Double(points.count) }
    public var maximum: Double { points.map(\.bpm).max() ?? 0 }

    public static func make(points: [RunHeartRatePoint], session: RunSession) -> Self? {
        let valid = points.filter {
            $0.bpm.isFinite && (20...300).contains($0.bpm) && session.containsActiveTime($0.date)
                && !$0.source.isEmpty && $0.source.count <= 200
        }
        let groups = Dictionary(grouping: valid, by: \.source).mapValues { values in
            Dictionary(grouping: values, by: \.date).compactMap { $0.value.first }.sorted { $0.date < $1.date }
        }
        guard let source = groups.keys.sorted(by: {
            let left = groups[$0]?.count ?? 0
            let right = groups[$1]?.count ?? 0
            return left == right ? $0 < $1 : left > right
        }).first, let samples = groups[source], !samples.isEmpty else { return nil }
        return Self(points: samples, source: source)
    }
}

public struct RunRecord: Codable, Equatable, Sendable, Identifiable {
    public var session: RunSession
    public var heartRates: [RunHeartRatePoint]
    public var linkedHealthWorkoutID: UUID?
    public var id: UUID { session.id }
    public var heartRate: RunHeartRateSummary? { .make(points: heartRates, session: session) }

    public init(session: RunSession, heartRates: [RunHeartRatePoint] = []) {
        self.session = session
        self.heartRates = heartRates
    }

    public func workout(weightKG: Double?, notes: String = "", effort: Int? = nil) throws -> WorkoutRecord {
        try session.validate()
        guard session.state == .finished, session.activeSeconds(at: session.lastCheckpoint) >= 1 else {
            throw DiaryError.invalidInput("本次跑步还没有可保存的运动时长。")
        }
        let metrics = RunWorkoutMetrics(durationSeconds: session.activeSeconds(at: session.lastCheckpoint),
            distanceMeters: session.distanceMeters, averageHeartRate: heartRate?.average,
            maximumHeartRate: heartRate?.maximum, estimatedActiveCalories: session.estimatedCalories(weightKG: weightKG))
        let calories = metrics.estimatedActiveCalories.flatMap { (0...5000).contains($0) ? $0 : nil }
        let heart = metrics.averageHeartRate.flatMap { (30...240).contains($0) ? Int($0.rounded()) : nil }
        let distance = metrics.distanceMeters <= 200_000 ? metrics.distanceMeters : nil
        let minutes = max(1, min(600, Int(ceil(metrics.durationSeconds / 60))))
        let requiresCompatibility = metrics.durationSeconds > 36_000 || distance == nil
            || (metrics.estimatedActiveCalories != nil && calories == nil)
            || (metrics.averageHeartRate != nil && heart == nil)
        let compatibilityNote = "兼容摘要供旧版本显示，完整跑步指标保存在新版本记录中。"
        let suffix = (notes.isEmpty ? "" : "\n") + compatibilityNote
        let finalNotes = requiresCompatibility && notes.count + suffix.count <= 500 ? notes + suffix : notes
        let workout = WorkoutRecord(id: id, date: session.startedAt, kind: .cardio, title: "户外跑步",
            durationMinutes: minutes, perceivedEffort: effort, caloriesBurned: calories,
            notes: finalNotes, cardio: CardioDetail(activity: .run, distanceMeters: distance, averageHeartRate: heart),
            runMetrics: metrics)
        try workout.validate()
        return workout
    }
}

/// 可同步的精确跑步摘要，旧字段继续满足既有客户端的数值约束。
public struct RunWorkoutMetrics: Codable, Equatable, Sendable {
    public let durationSeconds: Double
    public let distanceMeters: Double
    public let averageHeartRate: Double?
    public let maximumHeartRate: Double?
    public let estimatedActiveCalories: Double?

    public func updatingHeartRate(_ heart: RunHeartRateSummary?) -> Self {
        Self(durationSeconds: durationSeconds, distanceMeters: distanceMeters,
             averageHeartRate: heart?.average, maximumHeartRate: heart?.maximum,
             estimatedActiveCalories: estimatedActiveCalories)
    }

    func validate() throws {
        guard durationSeconds.isFinite, (1...604_800).contains(durationSeconds),
              distanceMeters.isFinite, (0...1_000_000).contains(distanceMeters),
              averageHeartRate.map({ $0.isFinite && (20...300).contains($0) }) ?? true,
              maximumHeartRate.map({ $0.isFinite && (20...300).contains($0) }) ?? true,
              estimatedActiveCalories.map({ $0.isFinite && (0...360_000).contains($0) }) ?? true else {
            throw DiaryError.invalidInput("跑步指标无效，原始记录已保留。")
        }
    }
}
