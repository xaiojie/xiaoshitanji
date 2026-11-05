import Foundation
import NutritionCore

/// 每天开工时留一份本机备份；失败不打扰用户。
@MainActor
enum BackupService {
    static let directory = DiaryBackup.directory(in: URL.documentsDirectory)
    private static var pendingBackup: Task<URL?, Never>?

    static var latestBackupDate: Date? {
        DiaryBackup.latest(in: directory)
            .flatMap { url in try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
    }

    @discardableResult
    static func backupIfNeeded(_ document: DiaryDocument) async -> URL? {
        if let pendingBackup { return await pendingBackup.value }
        guard !document.records.isEmpty || !document.weights.isEmpty || !document.workouts.isEmpty
            || !document.plans.isEmpty || !document.templates.isEmpty || !document.smoking.packs.isEmpty
            || document.profile != HealthProfile() || document.energy != nil else { return nil }
        let photos = URL.documentsDirectory.appending(path: "FoodDiary/Photos")
        let directory = directory
        let task = Task.detached(priority: .utility) {
            try? DiaryBackup.make(document, in: directory, photosDirectory: photos)
        }
        pendingBackup = task
        defer { pendingBackup = nil }
        return await task.value
    }
}
