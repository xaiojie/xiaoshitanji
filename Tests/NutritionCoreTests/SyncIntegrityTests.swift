import Foundation
import Testing
@testable import NutritionCore

@Suite("同步与备份完整性")
struct SyncIntegrityTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "sync-integrity-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func document(recordPhoto: String? = nil, packPhoto: String? = nil) throws -> DiaryDocument {
        var document = DiaryDocument(records: [MealRecord(foods: [
            .manual(name: "米饭", nutrition: Nutrition(calories: 150))
        ], photoFileName: recordPhoto)])
        try document.smoking.openPack(CigarettePack(product: CigaretteProduct(name: "测试"), photoFileName: packPhoto))
        return document
    }

    @Test func mergeIncludesRemoteWorkoutsAndPlansAndKeepsLocalEdits() throws {
        let workout = WorkoutRecord(kind: .cardio, title: "本机", durationMinutes: 30,
            cardio: CardioDetail(activity: .run, distanceMeters: 3000))
        var remoteCopy = workout
        remoteCopy.title = "远端旧值"
        let remoteWorkout = WorkoutRecord(kind: .cardio, title: "云端训练", durationMinutes: 20,
            cardio: CardioDetail(activity: .walk, distanceMeters: 1000))
        let localPlan = WorkoutPlan(name: "本机计划", kind: .cardio, cardio: CardioDetail(activity: .run))
        let remotePlan = WorkoutPlan(name: "远端计划", kind: .cardio, cardio: CardioDetail(activity: .walk))
        let local = DiaryDocument(workouts: [workout], plans: [localPlan])
        let remote = DiaryDocument(workouts: [remoteCopy, remoteWorkout], plans: [remotePlan])
        let merged = try local.merged(with: remote)
        #expect(merged.workouts.count == 2)
        #expect(merged.workouts.first { $0.id == workout.id }?.title == "本机")
        #expect(merged.plans.count == 2)
        let again = try merged.merged(with: remote)
        #expect(again.workouts.count == 2)
        #expect(again.plans.count == 2)
    }

    @Test func freshDeviceInheritsCloudProfileAndExistingLocalProfileKeepsPriority() throws {
        let remote = DiaryDocument(profile: HealthProfile(nickname: "云端昵称", avatarJPEG: Data([1, 2]),
            heightCM: 175, targetWeightKG: 65, heightUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000)))
        let fresh = try DiaryDocument().merged(with: remote)
        #expect(fresh.profile == remote.profile)
        let local = DiaryDocument(profile: HealthProfile(nickname: "本机昵称"))
        #expect(try local.merged(with: remote).profile == local.profile)
    }

    @Test func photoTransferIncludesMealAndPackAndUsesImmutableContentNames() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1, 2, 3]).write(to: root.appending(path: "meal.jpg"))
        try Data([4, 5, 6]).write(to: root.appending(path: "pack.jpg"))
        let original = try document(recordPhoto: "meal.jpg", packPhoto: "pack.jpg")
        let transfer = try original.photoTransfer(from: root)
        #expect(transfer.photos.count == 2)
        let mealName = try #require(transfer.document.records.first?.photoFileName)
        #expect(PhotoArchive.isTransferName(mealName))
        #expect(transfer.photos.first { $0.name == mealName }?.data == Data([1, 2, 3]))
        #expect(transfer.document.records[0].photoJPEG == nil)
        try Data([9]).write(to: root.appending(path: "meal.jpg"))
        let updated = try original.photoTransfer(from: root)
        #expect(updated.document.records[0].photoFileName != mealName)
        #expect(original.records[0].photoFileName == "meal.jpg")
    }

    @Test func photoTransferDeduplicatesAndRejectsMissingSource() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1, 2]).write(to: root.appending(path: "both.jpg"))
        let transfer = try document(recordPhoto: "both.jpg", packPhoto: "both.jpg").photoTransfer(from: root)
        #expect(transfer.photos.count == 1)
        #expect(throws: DiaryError.self) { try document(recordPhoto: "missing.jpg").photoTransfer(from: root) }
    }

    @Test func corruptedContentNamedSourceBlocksUploadAndBackup() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = PhotoArchive.transferName(for: Data([1, 2, 3]))
        try PhotoArchive.save(Data([9, 9, 9]), name: name, in: root)
        let source = try document(recordPhoto: name, packPhoto: name)
        #expect(throws: DiaryError.self) { try source.photoTransfer(from: root) }
        #expect(throws: DiaryError.self) { try DiaryBackup.data(for: source, photosDirectory: root) }
    }

    @Test func backupRestoresImagesAfterOriginalDirectoryIsGone() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let photos = root.appending(path: "Photos")
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: photos.appending(path: "meal.jpg"))
        try Data([4, 5]).write(to: photos.appending(path: "pack.jpg"))
        let source = try document(recordPhoto: "meal.jpg", packPhoto: "pack.jpg")
        let url = try DiaryBackup.make(source, in: root.appending(path: "Backups"), photosDirectory: photos)
        try FileManager.default.removeItem(at: photos)
        let restored = try DiaryBackup.restore(from: url)
        #expect(restored.records[0].photoJPEG == Data([1, 2, 3]))
        #expect(restored.smoking.packs[0].photoJPEG == Data([4, 5]))
        #expect(restored.records[0].photoFileName == nil)
        #expect(source.records[0].photoFileName == "meal.jpg")
    }

    @Test func oldMetadataBackupsCanBeCompletedWithOriginalPhotos() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try document(recordPhoto: "meal.jpg")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let url = root.appending(path: "diary-old.json")
        try encoder.encode(source).write(to: url)
        #expect(throws: DiaryError.self) { try DiaryBackup.restore(from: url) }
        try Data([7]).write(to: root.appending(path: "meal.jpg"))
        let restored = try DiaryBackup.restore(from: url, photosDirectory: root)
        #expect(restored.records[0].photoJPEG == Data([7]))
    }

    @Test func backupRejectsMissingPhotosBeforePublishingAFile() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let backups = root.appending(path: "Backups")
        #expect(throws: DiaryError.self) {
            try DiaryBackup.make(document(recordPhoto: "missing.jpg"), in: backups, photosDirectory: root)
        }
        #expect(DiaryBackup.backups(in: backups).isEmpty)
    }

    @Test func legacyNumericDatesRemainRestorable() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try document()
        let url = root.appending(path: "legacy.json")
        try JSONEncoder().encode(source).write(to: url)
        let restored = try DiaryBackup.restore(from: url)
        #expect(restored.records[0].date == source.records[0].date)
    }

    @Test func sameDayMetadataBackupIsUpgradedWithoutReplacingItsRecords() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try document(recordPhoto: "meal.jpg")
        let url = root.appending(path: DiaryBackup.filename(for: .now))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(source).write(to: url)
        try Data([7, 8]).write(to: root.appending(path: "meal.jpg"))
        let updated = try DiaryBackup.make(DiaryDocument(), in: root, photosDirectory: root)
        #expect(updated == url)
        let restored = try DiaryBackup.restore(from: updated)
        #expect(restored.records[0].id == source.records[0].id)
        #expect(restored.records[0].photoJPEG == Data([7, 8]))
    }

    @Test func pruningAlwaysKeepsTheNewRestorePoint() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        // A previous device clock can leave backups with dates later than today.
        for index in 0..<DiaryBackup.defaultKeeping {
            let url = root.appending(path: "diary-9999-12-31-\(index).json")
            try DiaryBackup.data(for: DiaryDocument()).write(to: url)
        }
        let url = try DiaryBackup.makeRestorePoint(document(), in: root)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(DiaryBackup.backups(in: root).count == DiaryBackup.defaultKeeping)
        #expect(try DiaryBackup.restore(from: url).records.count == 1)
    }

    @Test func packRejectsUnsafePhotoReferences() throws {
        let value = CigarettePack(product: CigaretteProduct(name: "测试"), photoFileName: "../secret")
        #expect(throws: DiaryError.self) { try value.validate() }
    }

    @Test func firstSyncDownloadsEvenWhenLoginReportsTheCurrentVersion() {
        let remote = CloudSyncState(version: 3, updatedAt: nil, checksum: nil)
        #expect(remote.needsDownload(knownVersion: 3, hasSynced: false))
        #expect(remote.needsDownload(knownVersion: nil, hasSynced: false))
        #expect(!remote.needsDownload(knownVersion: 3, hasSynced: true))
        #expect(remote.needsDownload(knownVersion: 2, hasSynced: true))
        #expect(!CloudSyncState(version: 0, updatedAt: nil, checksum: nil).needsDownload(knownVersion: nil, hasSynced: false))
    }


    @Test func materializingNewPhotoDoesNotOverwritePreviousImage() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var document = try document()
        document.records[0].photoJPEG = Data([1, 2])
        _ = try document.externalizePhotos(in: root)
        let originalName = try #require(document.records[0].photoFileName)
        document.records[0].photoJPEG = Data([3, 4])
        _ = try document.externalizePhotos(in: root)
        #expect(document.records[0].photoFileName != originalName)
        #expect(PhotoArchive.load(name: originalName, in: root) == Data([1, 2]))
    }

    @Test func explicitRecoveryPreservesUnreadableOriginalAndItsPhotos() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "diary.json")
        try Data("damaged original".utf8).write(to: url)
        let photos = root.appending(path: "Photos")
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        try Data([1, 2]).write(to: photos.appending(path: "old.jpg"))
        let recovery = root.appending(path: "Recovery")
        let store = DiaryStore(fileURL: url)
        #expect(throws: DiaryError.self) { try store.save(document()) }
        try store.restore(document(), preservingExistingIn: recovery)
        #expect(try Data(contentsOf: recovery.appending(path: "diary.json")) == Data("damaged original".utf8))
        #expect(try Data(contentsOf: recovery.appending(path: "Photos/old.jpg")) == Data([1, 2]))
        #expect(try store.load().records.count == 1)
    }

}
