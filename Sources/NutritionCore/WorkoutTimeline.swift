import Foundation

public struct WorkoutTimelineEntry: Identifiable, Sendable {
    public let local: WorkoutRecord?
    public let health: HealthWorkout?
    public let needsReview: Bool
    public var id: String { local.map { "local-\($0.id)" } ?? "health-\(health!.id)" }
    public var date: Date { local?.date ?? health!.date }
    public var title: String { local?.displayTitle ?? health!.title }
    public var minutes: Int { local.map { max(1, Int(ceil($0.effectiveDurationSeconds / 60))) } ?? health!.durationMinutes }
    public var calories: Double? { health?.activeCalories ?? local?.effectiveCalories }
    public var distanceMeters: Double? { local?.effectiveDistanceMeters ?? health?.distanceMeters }
    public var averageHeartRate: Double? { local?.effectiveHeartRate ?? health?.averageHeartRate }
    public var isRunning: Bool { local?.cardio?.activity == .run || health?.title == "跑步" }
    public var sourceText: String {
        if local != nil && health != nil { return "本机记录 · Apple 健康已关联" }
        return health != nil ? "Apple 健康" : "本机记录"
    }
}

public enum WorkoutTimeline {
    public static func make(local: [WorkoutRecord], health: [HealthWorkout],
                            links: [UUID: UUID] = [:]) -> [WorkoutTimelineEntry] {
        var used = Set<UUID>()
        var result: [WorkoutTimelineEntry] = []
        for workout in local {
            let candidates = candidates(for: workout, health: health).filter { !used.contains($0.id) }
            let explicit = links[workout.id].flatMap { id in health.first { $0.id == id && !used.contains(id) } }
            let unique = candidates.count == 1 && local.filter {
                Self.candidates(for: $0, health: candidates).count == 1
            }.count == 1
            let match = explicit ?? (unique ? candidates.first : nil)
            if let match { used.insert(match.id) }
            result.append(WorkoutTimelineEntry(local: workout, health: match,
                                                needsReview: match == nil && !candidates.isEmpty))
        }
        for workout in health where !used.contains(workout.id) {
            result.append(WorkoutTimelineEntry(local: nil, health: workout,
                needsReview: local.contains { !candidates(for: $0, health: [workout]).isEmpty }))
        }
        return result.sorted { $0.date > $1.date }
    }

    public static func candidates(for local: WorkoutRecord, health: [HealthWorkout]) -> [HealthWorkout] {
        health.filter { workout in
            guard local.kind == workout.kind, abs(local.date.timeIntervalSince(workout.date)) <= 120,
                  abs(local.durationMinutes - workout.durationMinutes) <= max(2, Int(Double(local.durationMinutes) * 0.15))
            else { return false }
            if local.kind == .cardio {
                guard let activity = local.cardio?.activity else { return false }
                let title = activity == .walk ? "步行" : activity.title
                guard workout.title == title else { return false }
            }
            if let left = local.cardio?.distanceMeters, let right = workout.distanceMeters {
                return abs(left - right) <= max(100, left * 0.15)
            }
            return true
        }
    }
}
