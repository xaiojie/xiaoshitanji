import Foundation
import Testing
@testable import NutritionCore

/// 显式开发工具，生成用于真机截图的样例文件，与 App 本机日记独立。
/// 设置 FOOD_DIARY_WRITE_DEMO_FIXTURE=1 后才会写入 /tmp/diary-seed.json。
struct SeedFixtureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FOOD_DIARY_WRITE_DEMO_FIXTURE"] == "1"))
    func writeSampleDiary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = Date()
        let today = calendar.startOfDay(for: now)

        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: today)!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func food(_ name: String, _ grams: Double, _ calories: Double, _ protein: Double,
                  _ carbs: Double, _ fat: Double, note: String = "") -> FoodItem {
            FoodItem(name: name, grams: grams, per100g: Nutrition(calories: calories, protein: protein,
                                                                  carbohydrates: carbs, fat: fat),
                     notes: note)
        }
        func meal(_ dayOffset: Int, _ kind: MealKind, _ hour: Int, _ foods: [FoodItem],
                  _ summary: String, _ text: String) -> MealRecord {
            MealRecord(date: at(dayOffset, hour), kind: kind, foods: foods, originalText: text,
                       source: .text, model: "deepseek-flash", summary: summary)
        }

        var records: [MealRecord] = []
        records.append(meal(0, .breakfast, 8, [
            food("燕麦粥", 250, 71, 2.5, 12.0, 1.4),
            food("水煮蛋", 60, 155, 13.0, 1.1, 10.6),
            food("无糖豆浆", 300, 33, 3.0, 1.2, 1.8)
        ], "燕麦粥、水煮蛋和一杯无糖豆浆，蛋白质够、热量克制。", "早餐：燕麦粥一碗，两个水煮蛋，一杯无糖豆浆"))
        records.append(meal(0, .lunch, 12, [
            food("牛肉面", 450, 122, 7.2, 16.5, 3.4),
            food("凉拌黄瓜", 120, 24, 1.0, 3.2, 0.6)
        ], "一碗牛肉面加小份凉菜，碳水和蛋白质都够。", "中午吃了牛肉面，加一份凉拌黄瓜"))
        records.append(meal(0, .snack, 15, [
            food("冰美式", 350, 2, 0.1, 0.0, 0.0),
            food("原味坚果", 25, 610, 20.0, 21.0, 53.0)
        ], "咖啡加一小把坚果，下午垫了一下。", "下午一杯冰美式，一小把坚果"))
        records.append(meal(0, .dinner, 20, [
            food("清蒸鲈鱼", 180, 105, 19.0, 0.0, 2.6),
            food("蒜蓉西兰花", 150, 48, 3.6, 6.0, 1.2),
            food("米饭", 150, 116, 2.6, 25.9, 0.3)
        ], "清蒸鱼配西兰花和半碗米饭，晚餐偏清淡。", "晚上清蒸鲈鱼，蒜蓉西兰花，半碗米饭"))
        records.append(meal(-1, .breakfast, 8, [
            food("全麦吐司", 80, 246, 9.0, 41.0, 3.5),
            food("煎蛋", 55, 196, 13.6, 0.8, 14.8),
            food("牛奶", 250, 54, 3.2, 4.8, 3.0)
        ], "吐司加煎蛋和牛奶，比较标准的早餐。", "全麦吐司两片，一个煎蛋，一杯牛奶"))
        records.append(meal(-1, .lunch, 12, [
            food("鸡胸肉沙拉", 320, 78, 9.5, 4.0, 2.4),
            food("杂粮饭", 150, 130, 3.4, 27.0, 1.0)
        ], "鸡胸肉沙拉配杂粮饭，控制了油。", "鸡胸肉沙拉，一小碗杂粮饭"))
        records.append(meal(-1, .dinner, 19, [
            food("番茄炒蛋", 220, 80, 4.8, 4.2, 5.0),
            food("米饭", 120, 116, 2.6, 25.9, 0.3)
        ], "家常番茄炒蛋配米饭。", "晚上番茄炒蛋，米饭"))
        records.append(meal(-2, .lunch, 12, [
            food("照烧鸡腿饭", 480, 148, 8.0, 18.0, 4.6)
        ], "外食照烧鸡腿饭，钠和糖偏高。", "中午外卖照烧鸡腿饭"))
        records.append(meal(-3, .lunch, 12, [
            food("三文鱼饭团", 220, 180, 7.0, 29.0, 4.2),
            food("味增汤", 250, 26, 2.0, 2.6, 0.8)
        ], "两个饭团加味增汤，简单一餐。", "便利店饭团和味增汤"))
        records.append(meal(-4, .dinner, 19, [
            food("火锅（清汤）", 600, 96, 7.8, 6.0, 5.2),
            food("蘸料", 40, 210, 3.0, 8.0, 18.0)
        ], "清汤火锅，蘸料是大头。", "和朋友吃清汤火锅，蘸料吃了两份"))

        var weights: [WeightRecord] = []
        for (offset, value) in [(0, 71.6), (-1, 71.9), (-2, 72.1), (-4, 72.3), (-6, 72.5),
                                (-8, 72.4), (-11, 72.8), (-14, 73.0), (-18, 73.2), (-21, 73.4)] {
            weights.append(WeightRecord(date: at(offset, 7, 20), kilograms: value))
        }

        let workouts: [WorkoutRecord] = [
            WorkoutRecord(date: at(0, 18, 30), kind: .strength, title: "推日 · 胸肩三头",
                          durationMinutes: 62, perceivedEffort: 7, caloriesBurned: 380,
                          exercises: [
                            StrengthExercise(name: "卧推", sets: [StrengthSet(reps: 8, weightKG: 60),
                                                                   StrengthSet(reps: 8, weightKG: 60),
                                                                   StrengthSet(reps: 6, weightKG: 65)]),
                            StrengthExercise(name: "哑铃肩推", sets: [StrengthSet(reps: 10, weightKG: 20),
                                                                       StrengthSet(reps: 10, weightKG: 20)]),
                            StrengthExercise(name: "绳索下压", sets: [StrengthSet(reps: 12, weightKG: 25),
                                                                      StrengthSet(reps: 12, weightKG: 25)])
                          ]),
            WorkoutRecord(date: at(-2, 7, 15), kind: .cardio, title: "晨跑",
                          durationMinutes: 32, perceivedEffort: 6, caloriesBurned: 320,
                          cardio: CardioDetail(activity: .run, distanceMeters: 5200, averageHeartRate: 152))
        ]

        let profile = HealthProfile(nickname: "奶蛙", heightCM: 178, targetWeightKG: 69,
                                    heightUpdatedAt: at(-60, 9))
        let energy = EnergySettings(sex: .male, birthYear: 1996, activity: .moderate,
                                    goalMode: .lose, weeklyRate: 0.25, updatedAt: at(-30, 9))

        var templates: [MealTemplate] = []
        templates.append(MealTemplate(record: records[0], name: "常吃的早餐", now: at(-5, 9)))
        templates.append(MealTemplate(record: records[5], name: "减脂午餐", now: at(-3, 13)))

        var smoking = SmokingDiary()
        try smoking.openPack(CigarettePack(product: CigaretteProduct(name: "软白", nicotineMG: 0.8,
                                                                      pricePerPack: 23),
                                           openedAt: at(-1, 21)))
        try smoking.record(.smoked, count: 1, date: at(0, 9, 40))
        try smoking.record(.smoked, count: 1, date: at(-1, 22, 10))

        var document = DiaryDocument(records: records, profile: profile, weights: weights,
                                     smoking: smoking, workouts: workouts, templates: templates,
                                     energy: energy)
        document.schemaVersion = DiaryDocument.currentSchemaVersion
        try document.validate()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: URL(fileURLWithPath: "/tmp/diary-seed.json"))
        #expect(data.count > 1000)
    }
}
