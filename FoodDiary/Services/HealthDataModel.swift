import Foundation
import HealthKit
import Observation
import NutritionCore

@MainActor
@Observable
final class HealthDataModel {
    private(set) var days: [HealthActivityDay] = []
    private(set) var weights: [WeightRecord] = []
    private(set) var heightCM: Double?
    private(set) var heightDate: Date?
    private(set) var lastRefresh: Date?
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private(set) var accessRequested = UserDefaults.standard.bool(forKey: "appleHealthAccessRequested")
    @ObservationIgnored private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var today: HealthActivityDay { days.first { Calendar.current.isDateInToday($0.date) } ?? HealthActivityDay(date: .now) }
    var hasData: Bool {
        !weights.isEmpty || heightCM != nil || days.contains { $0.steps != nil || $0.activeCalories != nil || $0.exerciseMinutes != nil || $0.distanceMeters != nil }
    }

    func connect() async {
        guard isAvailable else { errorMessage = "当前设备无法使用 Apple 健康。"; return }
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let identifiers: [HKQuantityTypeIdentifier] = [.stepCount, .activeEnergyBurned, .appleExerciseTime,
                                                          .distanceWalkingRunning, .bodyMass, .height]
            let types = Set<HKObjectType>(identifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) })
            try await store.requestAuthorization(toShare: [], read: types)
            accessRequested = true
            UserDefaults.standard.set(true, forKey: "appleHealthAccessRequested")
            try await loadSnapshot()
        } catch { errorMessage = "暂时无法读取 Apple 健康，请解锁手机，并在健康 App 中检查小食痰记的访问权限。" }
    }

    func refresh() async {
        guard accessRequested, isAvailable, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { try await loadSnapshot() }
        catch { errorMessage = "本次健康数据刷新失败，已有记录仍可查看。请解锁手机后重试。" }
    }

    private func loadSnapshot() async throws {
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -6, to: today) else { return }
        async let steps = Self.readDaily(store, type: .stepCount, unit: .count(), start: start, end: now, calendar: calendar)
        async let calories = Self.readDaily(store, type: .activeEnergyBurned, unit: .kilocalorie(), start: start, end: now, calendar: calendar)
        async let minutes = Self.readDaily(store, type: .appleExerciseTime, unit: .minute(), start: start, end: now, calendar: calendar)
        async let distance = Self.readDaily(store, type: .distanceWalkingRunning, unit: .meter(), start: start, end: now, calendar: calendar)
        async let measurements = Self.readWeights(store)
        async let height = Self.readHeight(store)
        let values = try await (steps, calories, minutes, distance, measurements, height)
        days = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return HealthActivityDay(date: date, steps: values.0[date], activeCalories: values.1[date],
                                     exerciseMinutes: values.2[date], distanceMeters: values.3[date])
        }
        weights = values.4
        heightCM = values.5?.value
        heightDate = values.5?.date
        lastRefresh = now
    }

    nonisolated private static func readDaily(_ store: HKHealthStore, type identifier: HKQuantityTypeIdentifier,
                                              unit: HKUnit, start: Date, end: Date, calendar: Calendar) async throws -> [Date: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [:] }
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { query, collection, error in
                defer { store.stop(query) }
                if let error { continuation.resume(throwing: error); return }
                var values: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    if let quantity = statistics.sumQuantity() {
                        let value = quantity.doubleValue(for: unit)
                        if value.isFinite && value >= 0 { values[calendar.startOfDay(for: statistics.startDate)] = value }
                    }
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    nonisolated private static func readWeights(_ store: HKHealthStore) async throws -> [WeightRecord] {
        guard let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 500,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let records = (samples as? [HKQuantitySample] ?? []).compactMap { sample -> WeightRecord? in
                    let value = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                    let record = WeightRecord(id: sample.uuid, date: sample.startDate, kilograms: value, source: .appleHealth)
                    do { try record.validate(); return record }
                    catch { return nil }
                }
                continuation.resume(returning: records)
            }
            store.execute(query)
        }
    }

    nonisolated private static func readHeight(_ store: HKHealthStore) async throws -> (value: Double, date: Date)? {
        guard let type = HKObjectType.quantityType(forIdentifier: .height) else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let value = sample.quantity.doubleValue(for: .meterUnit(with: .centi))
                continuation.resume(returning: (50...250).contains(value) ? (value, sample.startDate) : nil)
            }
            store.execute(query)
        }
    }
}
