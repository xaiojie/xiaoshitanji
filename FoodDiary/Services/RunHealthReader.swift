import Foundation
import HealthKit
import NutritionCore

extension HealthDataModel {
    func heartRates(for session: RunSession) async throws -> [RunHeartRatePoint] {
        guard accessRequested, isAvailable else { return [] }
        let store = HKHealthStore()
        let type = HKQuantityType(.heartRate)
        let end = session.endedAt ?? session.lastCheckpoint
        let samples: [RunHeartRatePoint] = try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: session.startedAt, end: end,
                                                       options: [.strictStartDate, .strictEndDate])
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 100_000,
                                     sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) {
                _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let values = (samples as? [HKQuantitySample] ?? []).map {
                    RunHeartRatePoint(date: $0.startDate,
                        bpm: $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
                        source: $0.sourceRevision.source.name)
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
        try Task.checkCancellation()
        return RunHeartRateSummary.make(points: samples, session: session)?.points ?? []
    }
}
