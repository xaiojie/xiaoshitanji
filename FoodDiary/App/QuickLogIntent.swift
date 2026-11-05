import AppIntents
import Foundation
import NutritionCore

/// 快捷指令 / Siri：「记一餐」把一句话交给 App，打开时自动填进记录页。
struct LogMealIntent: AppIntent {
    static var title: LocalizedStringResource { "记一餐" }
    static var description: IntentDescription { IntentDescription("说一句吃了什么，打开小食痰记时自动填好。") }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "吃了什么", requestValueDialog: "这一餐吃了什么？")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingMeal.store(text)
        return .result()
    }
}

struct DiaryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogMealIntent(),
                    phrases: ["用 \(.applicationName) 记一餐", "让 \(.applicationName) 记一餐"],
                    shortTitle: "记一餐",
                    systemImageName: "fork.knife")
    }
}

enum PendingMeal {
    static let key = "pendingMealText"

    static func store(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: key)
    }

    /// 取出即清空，避免每次启动都重复填。
    static func take() -> String? {
        defer { UserDefaults.standard.removeObject(forKey: key) }
        guard let text = UserDefaults.standard.string(forKey: key),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// 用一句话开一条草稿，餐次按当前时间猜。
    static func draft(from text: String, now: Date = .now) -> MealRecord {
        var record = MealRecord.draft(on: now, kind: MealKind.suggested(for: now), now: now)
        record.updateInput(text: text, photoJPEG: nil)
        return record
    }
}
