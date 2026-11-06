import Foundation
import Testing
@testable import NutritionCore

@Suite("跑步静止漂移")
struct RunDriftTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func location(_ meters: Double, seconds: Double, accuracy: Double = 15) -> RunLocation {
        RunLocation(latitude: 0, longitude: meters / 111_194.9266,
                    timestamp: start.addingTimeInterval(seconds), horizontalAccuracy: accuracy)
    }

    @Test func officeJitterWithoutSpeedDoesNotCreateDistance() {
        var run = RunSession(startedAt: start)
        let offsets = [0.0, 6, -3, 8, 1, -5, 5, -7, 3, 0]
        for index in 0...300 {
            let time = Double(index * 2)
            run.ingest(location(offsets[index % offsets.count], seconds: time),
                       receivedAt: start.addingTimeInterval(time))
        }
        run.checkpoint(at: start.addingTimeInterval(600))
        #expect(run.distanceMeters == 0)
        #expect(run.averagePace == nil)
        #expect(run.currentPace(at: start.addingTimeInterval(600)) == nil)
        #expect(!run.goalReached)
    }

    @Test func sustainedMovementWithoutSpeedBackfillsConfirmedPath() {
        var run = RunSession(startedAt: start)
        for index in 0...20 {
            let time = Double(index) * 1.5
            run.ingest(location(Double(index * 5), seconds: time, accuracy: 5),
                       receivedAt: start.addingTimeInterval(time))
        }
        #expect(run.distanceMeters >= 85 && run.distanceMeters <= 100.1)
    }

    @Test func stationarySpeedRejectsPositionsThatWander() {
        var run = RunSession(startedAt: start)
        for index in 0...60 {
            let seconds = Double(index * 2)
            var fix = location(Double(index % 6) * 6, seconds: seconds, accuracy: 8)
            fix.speed = 0.1
            fix.speedAccuracy = 0.3
            run.ingest(fix, receivedAt: start.addingTimeInterval(seconds))
        }
        #expect(run.distanceMeters == 0)
        #expect(run.averagePace == nil)
    }

    @Test func motionStationaryOverridesFalseMovingSpeed() {
        var run = RunSession(startedAt: start)
        for index in 0...10 {
            let seconds = Double(index * 2)
            var fix = location(Double(index * 5), seconds: seconds, accuracy: 5)
            fix.speed = 2.5
            fix.speedAccuracy = 0.2
            fix.movement = .stationary
            run.ingest(fix, receivedAt: start.addingTimeInterval(seconds))
        }
        #expect(run.distanceMeters == 0)
    }

    @Test func movementAfterSittingStartsWithoutBridgingDrift() {
        var run = RunSession(startedAt: start)
        for index in 0...10 {
            let seconds = Double(index * 2)
            var fix = location(Double(index % 5) * 5, seconds: seconds)
            fix.movement = .stationary
            run.ingest(fix, receivedAt: start.addingTimeInterval(seconds))
        }
        for index in 0...3 {
            let seconds = 30 + Double(index * 5)
            var fix = location(100 + Double(index * 15), seconds: seconds, accuracy: 5)
            fix.speed = 3
            fix.speedAccuracy = 0.2
            fix.movement = .moving
            run.ingest(fix, receivedAt: start.addingTimeInterval(seconds))
        }
        #expect(abs(run.distanceMeters - 45) < 0.1)
        var stopped = location(160, seconds: 46, accuracy: 5)
        stopped.movement = .stationary
        run.ingest(stopped, receivedAt: start.addingTimeInterval(46))
        #expect(abs(run.distanceMeters - 45) < 0.1)
        #expect(run.currentPace(at: start.addingTimeInterval(46)) == nil)
    }

    @Test func ordinarySlowWalkingStillCounts() {
        var run = RunSession(startedAt: start)
        for index in 0...10 {
            let seconds = Double(index * 5)
            var fix = location(Double(index * 4), seconds: seconds, accuracy: 5)
            fix.speed = 0.8
            fix.speedAccuracy = 0.2
            fix.movement = .moving
            run.ingest(fix, receivedAt: start.addingTimeInterval(seconds))
        }
        #expect(abs(run.distanceMeters - 40) < 0.1)
    }

    @Test func oldDraftsDecodeWithoutNewMotionFields() throws {
        var run = RunSession(startedAt: start)
        var fix = location(0, seconds: 0)
        fix.speed = 3
        fix.speedAccuracy = 0.2
        run.ingest(fix, receivedAt: start)
        let data = try JSONEncoder().encode(run)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var points = try #require(object["points"] as? [[String: Any]])
        for index in points.indices {
            var value = try #require(points[index]["location"] as? [String: Any])
            for key in ["speed", "speedAccuracy", "movement"] { value.removeValue(forKey: key) }
            points[index]["location"] = value
        }
        object["points"] = points
        object.removeValue(forKey: "movementCandidates")
        object.removeValue(forKey: "movementUnconfirmed")
        let decoded = try JSONDecoder().decode(RunSession.self, from: JSONSerialization.data(withJSONObject: object))
        try decoded.validate()
        #expect(decoded.id == run.id)
        #expect(decoded.points.count == 1)
    }

    @Test func unclassifiedStoppingDoesNotReusePastMovementAsEvidence() {
        var run = RunSession(startedAt: start)
        for index in 0...10 {
            let seconds = Double(index * 2)
            run.ingest(location(Double(index * 6), seconds: seconds, accuracy: 5),
                       receivedAt: start.addingTimeInterval(seconds))
        }
        let before = run.distanceMeters
        for (index, meters) in [64.0, 58, 63, 59, 62].enumerated() {
            let seconds = 22 + Double(index * 2)
            run.ingest(location(meters, seconds: seconds, accuracy: 5),
                       receivedAt: start.addingTimeInterval(seconds))
        }
        #expect(abs(run.distanceMeters - before) < 0.1)
        #expect(run.currentPace(at: start.addingTimeInterval(30)) == nil)
    }

    @Test func lowPrecisionWalkingWithoutSpeedStillAccumulatesConfirmedDistance() {
        var run = RunSession(startedAt: start)
        for index in 0...120 {
            let seconds = Double(index * 5)
            run.ingest(location(seconds, seconds: seconds, accuracy: 20),
                       receivedAt: start.addingTimeInterval(seconds))
        }
        #expect(run.distanceMeters >= 560 && run.distanceMeters <= 600.1)
    }

    @Test func lowPrecisionJoggingWithoutMotionPermissionStillCounts() {
        var run = RunSession(startedAt: start)
        for index in 0...120 {
            let seconds = Double(index * 5)
            run.ingest(location(seconds * 2, seconds: seconds, accuracy: 35),
                       receivedAt: start.addingTimeInterval(seconds))
        }
        #expect(run.distanceMeters >= 1130 && run.distanceMeters <= 1200.1)
    }
}
