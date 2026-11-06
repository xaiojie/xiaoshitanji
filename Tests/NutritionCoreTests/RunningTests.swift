import Foundation
import Testing
@testable import NutritionCore

@Suite("GPS 跑步")
struct RunningTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func point(_ meters: Double, _ seconds: Double, accuracy: Double = 5) -> RunLocation {
        RunLocation(latitude: 0, longitude: meters / 111_194.9266,
                    timestamp: start.addingTimeInterval(seconds), horizontalAccuracy: accuracy)
    }

    @Test func pauseExcludesTimeAndDoesNotBridgeMovement() {
        var run = RunSession(startedAt: start)
        run.ingest(point(0, 0), receivedAt: start)
        run.ingest(point(40, 10), receivedAt: start.addingTimeInterval(10))
        run.pause(at: start.addingTimeInterval(10))
        run.resume(at: start.addingTimeInterval(100))
        run.ingest(point(400, 100), receivedAt: start.addingTimeInterval(100))
        run.ingest(point(440, 110), receivedAt: start.addingTimeInterval(110))
        run.finish(at: start.addingTimeInterval(110))
        #expect(abs(run.distanceMeters - 80) < 0.1)
        #expect(run.activeSeconds(at: start.addingTimeInterval(500)) == 20)
        #expect(Set(run.points.map(\.segment)).count == 2)
    }

    @Test func inaccurateOldAndTeleportingPointsDoNotInflateDistance() {
        var run = RunSession(startedAt: start)
        run.ingest(point(0, 0), receivedAt: start)
        run.ingest(point(40, 10), receivedAt: start.addingTimeInterval(10))
        run.ingest(point(5_000, 11), receivedAt: start.addingTimeInterval(11))
        run.ingest(point(44, 12), receivedAt: start.addingTimeInterval(12))
        run.ingest(point(900, 13, accuracy: 100), receivedAt: start.addingTimeInterval(13))
        run.ingest(point(48, 14), receivedAt: start.addingTimeInterval(14))
        run.ingest(point(100, 15), receivedAt: start.addingTimeInterval(100))
        #expect(abs(run.distanceMeters - 40) < 0.1)
        #expect(run.points.count == 4)
    }

    @Test func signalGapStartsANewTrackSegment() {
        var run = RunSession(startedAt: start)
        run.ingest(point(0, 0), receivedAt: start)
        run.ingest(point(40, 10), receivedAt: start.addingTimeInterval(10))
        run.ingest(point(400, 100), receivedAt: start.addingTimeInterval(100))
        #expect(abs(run.distanceMeters - 40) < 0.1)
        #expect(run.points.last?.segment != run.points.first?.segment)
        #expect(run.currentPace(at: start.addingTimeInterval(150)) == nil)
    }

    @Test func kilometerSplitsInterpolateAndTargetFiresOnce() throws {
        var run = RunSession(startedAt: start, targetMeters: 1_000)
        var alerts = 0
        for index in 0...30 {
            let seconds = Double(index * 10)
            if run.ingest(point(Double(index * 40), seconds),
                          receivedAt: start.addingTimeInterval(seconds)) { alerts += 1 }
        }
        run.finish(at: start.addingTimeInterval(300))
        #expect(alerts == 1)
        #expect(run.goalReached)
        #expect(run.splits.count == 2)
        #expect(abs(try #require(run.splits.first).seconds - 250) < 0.1)
        #expect(abs(try #require(run.splits.last).distanceMeters - 200) < 0.1)
        #expect(abs(try #require(run.averagePace) - 250) < 0.1)
    }

    @Test func restartClosesAtPersistedCheckpoint() {
        var run = RunSession(startedAt: start)
        run.checkpoint(at: start.addingTimeInterval(30))
        run.recover()
        #expect(run.state == .paused)
        #expect(run.activeSeconds(at: start.addingTimeInterval(3600)) == 30)
        run.resume(at: start.addingTimeInterval(3600))
        run.finish(at: start.addingTimeInterval(3610))
        #expect(run.activeSeconds(at: start.addingTimeInterval(4000)) == 40)
    }

    @Test func heartRateUsesActiveIntervalsAndOneSource() throws {
        var run = RunSession(startedAt: start)
        run.pause(at: start.addingTimeInterval(20))
        run.resume(at: start.addingTimeInterval(40))
        run.finish(at: start.addingTimeInterval(60))
        let points = [
            RunHeartRatePoint(date: start.addingTimeInterval(10), bpm: 120, source: "Watch"),
            RunHeartRatePoint(date: start.addingTimeInterval(30), bpm: 200, source: "Watch"),
            RunHeartRatePoint(date: start.addingTimeInterval(50), bpm: 140, source: "Watch"),
            RunHeartRatePoint(date: start.addingTimeInterval(10), bpm: 120, source: "Watch"),
            RunHeartRatePoint(date: start.addingTimeInterval(70), bpm: 210, source: "Watch"),
            RunHeartRatePoint(date: start.addingTimeInterval(12), bpm: 180, source: "Other")
        ]
        let summary = try #require(RunHeartRateSummary.make(points: points, session: run))
        #expect(summary.average == 130)
        #expect(summary.maximum == 140)
        #expect(summary.points.count == 2)
        #expect(summary.source == "Watch")
    }

    @Test func targetAndMissingMetricsRemainExplicit() throws {
        #expect(try RunSession.targetMeters(from: "5.5") == 5_500)
        #expect(throws: (any Error).self) { try RunSession.targetMeters(from: "0") }
        #expect(throws: (any Error).self) { try RunSession.targetMeters(from: "nan") }
        let run = RunSession(startedAt: start)
        #expect(run.averagePace == nil)
        #expect(run.estimatedCalories(weightKG: nil) == nil)
        #expect(RunHeartRateSummary.make(points: [], session: run) == nil)
    }

    @Test func archiveRetriesUseTheSameIDAndCorruptionIsReported() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = RunArchive(directory: directory)
        var run = RunSession(startedAt: start)
        run.checkpoint(at: start.addingTimeInterval(30))
        try archive.saveDraft(run)
        #expect(try archive.loadDraft()?.id == run.id)
        run.finish(at: start.addingTimeInterval(40))
        let record = RunRecord(session: run)
        try archive.save(record)
        try archive.save(record)
        #expect(try archive.records().count == 1)
        #expect(try record.workout(weightKG: nil).id == run.id)
        try archive.remove(id: run.id)
        #expect(try archive.records().isEmpty)
        try Data("broken".utf8).write(to: directory.appending(path: "draft.json"))
        #expect(throws: (any Error).self) { try archive.loadDraft() }
    }

    @Test func extendedRunMetricsKeepLegacySummaryReadable() throws {
        var run = RunSession(startedAt: start, targetMeters: 200_000)
        for index in 0...2001 {
            run.ingest(point(Double(index * 100), Double(index * 10)),
                       receivedAt: start.addingTimeInterval(Double(index * 10)))
        }
        run.finish(at: start.addingTimeInterval(20_010))
        let record = RunRecord(session: run, heartRates: [
            RunHeartRatePoint(date: start.addingTimeInterval(30), bpm: 250, source: "Watch")
        ])
        let summary = try record.workout(weightKG: 100)
        #expect(abs(summary.effectiveDistanceMeters! - 200_100) < 0.1)
        #expect(summary.effectiveHeartRate == 250)
        #expect(summary.effectiveCalories! > 5_000)
        #expect(summary.cardio?.distanceMeters == nil)
        #expect(summary.cardio?.averageHeartRate == nil)
        try summary.validate()
        let encoded = try JSONEncoder().encode(summary)
        let json = try JSONSerialization.jsonObject(with: encoded)
        var legacy = try #require(json as? [String: Any])
        legacy.removeValue(forKey: "runMetrics")
        let old = try JSONDecoder().decode(WorkoutRecord.self, from: JSONSerialization.data(withJSONObject: legacy))
        try old.validate()
        #expect(old.runMetrics == nil)
    }

    @Test func longDurationIsPreservedExactly() throws {
        var run = RunSession(startedAt: start)
        run.finish(at: start.addingTimeInterval(40_000))
        let summary = try RunRecord(session: run).workout(weightKG: nil)
        #expect(summary.effectiveDurationSeconds == 40_000)
        #expect(summary.durationMinutes == 600)
        #expect(summary.notes.contains("兼容摘要"))
    }

    @Test func corruptHistoryDoesNotHideValidHistoryOrDraft() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = RunArchive(directory: directory)
        var run = RunSession(startedAt: start)
        try archive.saveDraft(run)
        run.finish(at: start.addingTimeInterval(60))
        try archive.save(RunRecord(session: run))
        try Data("broken".utf8).write(to: directory.appending(path: "\(UUID()).json"))
        let snapshot = try archive.loadRecords()
        #expect(snapshot.records.count == 1)
        #expect(snapshot.unreadableFiles.count == 1)
        #expect(try archive.loadDraft()?.id == run.id)
        try Data("broken-draft".utf8).write(to: directory.appending(path: "draft.json"))
        let preserved = try archive.preserveUnreadableDraft()
        #expect(try Data(contentsOf: #require(preserved)) == Data("broken-draft".utf8))
        #expect(try archive.loadDraft() == nil)
    }

    @Test func interruptedSaveRetainsArchivedHeartRateAndLink() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = RunArchive(directory: directory)
        var run = RunSession(startedAt: start)
        run.finish(at: start.addingTimeInterval(60))
        try archive.saveDraft(run)
        var original = RunRecord(session: run, heartRates: [
            RunHeartRatePoint(date: start.addingTimeInterval(30), bpm: 140, source: "Watch")
        ])
        original.linkedHealthWorkoutID = UUID()
        try archive.save(original)
        let reopened = RunArchive(directory: directory)
        let draft = try reopened.loadDraft()
        let reconstructed = RunRecord(session: try #require(draft))
        let result = try reopened.save(reconstructed)
        #expect(result.heartRates == original.heartRates)
        #expect(result.linkedHealthWorkoutID == original.linkedHealthWorkoutID)
        #expect(try result.workout(weightKG: nil).effectiveHeartRate == 140)
    }

    @Test func pendingDeletionSurvivesSummaryRemovalUntilCleanupFinishes() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = RunArchive(directory: directory)
        var run = RunSession(startedAt: start)
        run.finish(at: start.addingTimeInterval(60))
        let record = RunRecord(session: run)
        try archive.save(record)
        var document = DiaryDocument(workouts: [try record.workout(weightKG: nil)])
        try archive.markForDeletion(id: record.id)
        document.removeWorkout(id: record.id)
        let reopened = RunArchive(directory: directory)
        #expect(document.workouts.isEmpty)
        #expect(try reopened.pendingDeletions().contains(record.id))
        try reopened.finishDeletion(id: record.id)
        #expect(try reopened.pendingDeletions().isEmpty)
        #expect(try reopened.records().isEmpty)
    }
}
