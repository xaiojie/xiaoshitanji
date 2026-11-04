import Foundation
import NutritionCore

/// 每天开工时留一份本机备份；失败不打扰用户。
enum BackupService {
    static let directory = DiaryBackup.directory(in: URL.documentsDirectory)

    static var latestBackupDate: Date? {
        DiaryBackup.latest(in: directory)
            .flatMap { url in try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
    }

    @discardableResult
    static func backupIfNeeded(_ document: DiaryDocument) -> URL? {
        guard !document.records.isEmpty else { return nil }
        return try? DiaryBackup.make(document, in: directory)
    }
}
