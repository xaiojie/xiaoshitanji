import Foundation
import Testing
@testable import NutritionCore

@Suite("训练计划")
struct WorkoutPlanTests {
    private func plan() -> WorkoutPlan {
        WorkoutPlan(name: "下肢日", kind: .strength, plannedMinutes: 50, exercises: [
            PlanExercise(name: "深蹲", sets: 4, reps: 6, weightKG: 80),
            PlanExercise(name: "硬拉", sets: 3, reps: 5, weightKG: 100)
        ])
    }

    @Test("计划生成训练：组数展开、时长继承")
    func makesWorkout() throws {
        let workout = plan().makeWorkout()
        try workout.validate()
        #expect(workout.exercises.count == 2)
        #expect(workout.exercises[0].sets.count == 4)
        #expect(workout.exercises[1].sets.count == 3)
        #expect(workout.durationMinutes == 50)
        #expect(workout.volume == 4 * 6 * 80 + 3 * 5 * 100)
        #expect(workout.displayTitle == "下肢日")
    }

    @Test("校验：名称、时长、动作、有氧项目")
    func validation() {
        #expect(throws: (any Error).self) { try WorkoutPlan(name: " ").validate() }
        #expect(throws: (any Error).self) { try WorkoutPlan(name: "空", exercises: []).validate() }
        #expect(throws: (any Error).self) {
            try WorkoutPlan(name: "坏组数", exercises: [PlanExercise(name: "深蹲", sets: 0)]).validate()
        }
        #expect(throws: (any Error).self) { try WorkoutPlan(name: "跑", kind: .cardio).validate() }
        let cardio = WorkoutPlan(name: "晨跑", kind: .cardio, cardio: CardioDetail(activity: .run, distanceMeters: 5000))
        #expect(throws: Never.self) { try cardio.validate() }
        #expect(cardio.summary.contains("跑步"))
    }

    @Test("从旧训练建计划，保留组数与重量")
    func planFromWorkout() {
        let workout = WorkoutRecord(kind: .strength, title: "推日", durationMinutes: 40,
                                    exercises: [StrengthExercise(name: "卧推",
                                                                 sets: [StrengthSet(reps: 8, weightKG: 60),
                                                                        StrengthSet(reps: 8, weightKG: 65)])])
        let plan = WorkoutPlan(workout: workout, name: "")
        #expect(plan.name == "推日")
        #expect(plan.exercises[0].sets == 2)
        #expect(plan.exercises[0].weightKG == 60)
        #expect(plan.plannedMinutes == 40)
    }

    @Test("文档：保存、上限 20、按最近使用排序、从计划开练")
    func documentPlans() throws {
        var document = DiaryDocument()
        let base = plan()
        try document.savePlan(base)
        #expect(document.plans.count == 1)
        #expect(document.recentPlans(limit: 1).first?.id == base.id)

        let workout = try document.startWorkout(fromPlan: base.id)
        #expect(workout != nil)
        #expect(document.workouts.count == 1)
        #expect(document.plans[0].useCount == 1)

        for index in 0..<25 {
            try document.savePlan(WorkoutPlan(name: "计划\(index)", exercises: [PlanExercise(name: "深蹲")]))
        }
        #expect(document.plans.count == 20)

        document.removePlan(id: base.id)
        #expect(!document.plans.contains { $0.id == base.id })
        #expect(try document.startWorkout(fromPlan: UUID()) == nil)
    }

    @Test("v4 旧文件读得出空计划，新文件写 v5")
    func legacy() throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var old = DiaryDocument()
        old.schemaVersion = 4
        let decoded = try decoder.decode(DiaryDocument.self, from: encoder.encode(old))
        #expect(decoded.plans.isEmpty)
        #expect(decoded.schemaVersion == 4)
        #expect(try decoder.decode(DiaryDocument.self, from: encoder.encode(DiaryDocument())).schemaVersion == 5)
    }
}
