import Foundation
import Testing
@testable import NutritionCore

@Suite("训练记录")
struct WorkoutTests {
    private func strength() -> WorkoutRecord {
        WorkoutRecord(kind: .strength, title: "推日", durationMinutes: 60, perceivedEffort: 8,
                      exercises: [
                        StrengthExercise(name: "卧推", sets: [StrengthSet(reps: 8, weightKG: 60),
                                                          StrengthSet(reps: 8, weightKG: 65)]),
                        StrengthExercise(name: "肩推", sets: [StrengthSet(reps: 10, weightKG: 20)])
                      ])
    }

    @Test("力量训练的容量与组数")
    func volume() {
        let workout = strength()
        #expect(workout.volume == 8 * 60 + 8 * 65 + 10 * 20)
        #expect(workout.totalSets == 3)
        #expect(workout.displayTitle == "推日")
        #expect(WorkoutSummary.stats(for: DiaryDocument(workouts: [workout])).strengthVolume == workout.volume)
    }

    @Test("有氧需要项目，力量需要动作")
    func validationRules() {
        #expect(throws: (any Error).self) { try WorkoutRecord(kind: .cardio).validate() }
        #expect(throws: (any Error).self) { try WorkoutRecord(kind: .strength, exercises: []).validate() }
        #expect(throws: (any Error).self) {
            try WorkoutRecord(kind: .strength, durationMinutes: 0,
                              exercises: [StrengthExercise(name: "深蹲", sets: [StrengthSet(reps: 5)])]).validate()
        }
        #expect(throws: (any Error).self) {
            try StrengthSet(reps: 0, weightKG: 100).validate()
        }
        #expect(throws: (any Error).self) {
            try CardioDetail(activity: .run, distanceMeters: 250_000).validate()
        }
    }

    @Test("有氧可以只写距离与心率")
    func cardio() throws {
        let workout = WorkoutRecord(kind: .cardio, title: "", durationMinutes: 35,
                                    cardio: CardioDetail(activity: .run, distanceMeters: 5000, averageHeartRate: 148))
        try workout.validate()
        #expect(workout.displayTitle == "跑步")
        let stats = WorkoutSummary.stats(for: DiaryDocument(workouts: [workout]))
        #expect(stats.minutes == 35)
        #expect(stats.cardioMeters == 5000)
    }

    @Test("训练增删与当天筛选")
    func documentWorkouts() throws {
        var document = DiaryDocument()
        let workout = strength()
        try document.saveWorkout(workout)
        #expect(document.workouts.count == 1)
        #expect(document.workouts(on: .now).count == 1)
        #expect(document.workouts(on: Date(timeIntervalSince1970: 0)).isEmpty)
        try document.saveWorkout(workout)
        #expect(document.workouts.count == 1)
        document.removeWorkout(id: workout.id)
        #expect(document.workouts.isEmpty)
    }

    @Test("v2 旧文件仍能读，新文件写 v4")
    func legacyCompatibility() throws {
        var document = DiaryDocument(records: [])
        document.schemaVersion = 2
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(document)
        let decoded = try decoder.decode(DiaryDocument.self, from: data)
        #expect(decoded.workouts.isEmpty)
        #expect(decoded.schemaVersion == 2)

        let fresh = try decoder.decode(DiaryDocument.self, from: encoder.encode(DiaryDocument()))
        #expect(fresh.schemaVersion == 4)
    }
}
