import Foundation
import Testing
@testable import NutritionCore

@Suite("本机备份")
struct BackupTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "backup-tests-\(UUID().uuidString)")
    }

    private func sample() -> DiaryDocument {
        DiaryDocument(records: [
            MealRecord(date: Date(timeIntervalSince1970: 1_700_000_000), kind: .dinner,
                       foods: [.manual(name: "米饭", nutrition: Nutrition(calories: 200, protein: 4,
                                                                         carbohydrates: 44, fat: 0.5),
                                       grams: 150)], source: .manual, summary: "测试")
        ])
    }

    @Test("同一天只写一份，文件名带日期")
    func writesOncePerDay() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let first = try DiaryBackup.make(sample(), in: directory, now: now)
        let second = try DiaryBackup.make(sample(), in: directory, now: now.addingTimeInterval(3600))
        #expect(first == second)
        #expect(first.lastPathComponent.hasPrefix("diary-"))
        #expect(DiaryBackup.backups(in: directory).count == 1)
    }

    @Test("只保留最近 N 份")
    func prunesOldBackups() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for offset in 0..<5 {
            try DiaryBackup.make(sample(), in: directory,
                                 now: base.addingTimeInterval(Double(offset) * 86_400), keeping: 3)
        }
        #expect(DiaryBackup.backups(in: directory).count == 3)
        #expect(DiaryBackup.latest(in: directory)?.lastPathComponent.contains("2023-11-1") ?? false)
    }

    @Test("备份能还原成同一份文档")
    func restoresRoundTrip() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = sample()
        let url = try DiaryBackup.make(document, in: directory)
        let restored = try DiaryBackup.restore(from: url)
        #expect(restored.records.count == 1)
        #expect(restored.records[0].foods[0].name == "米饭")
        #expect(restored.schemaVersion == DiaryDocument.currentSchemaVersion)
    }

    @Test("坏文件会报错")
    func rejectsBrokenFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "diary-broken.json")
        try Data("not json".utf8).write(to: url)
        #expect(throws: (any Error).self) { try DiaryBackup.restore(from: url) }
    }
}
