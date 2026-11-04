import Foundation
import HealthKit
import Observation
import NutritionCore

struct WellnessHealthData: Sendable {
    var days: [HealthActivityDay] = []
    var weights: [WeightRecord] = []
    var heightCM: Double?
    var heightDate: Date?
    var earliestDate: Date?
    var workouts: [HealthWorkout] = []
}

@MainActor
@Observable
final class HealthDataModel {
    private(set) var days: [HealthActivityDay] = []
    private(set) var weights: [WeightRecord] = []
    private(set) var heightCM: Double?
    private(set) var heightDate: Date?
    private(set) var workouts: [HealthWorkout] = []
    private(set) var lastRefresh: Date?
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private(set) var accessRequested = UserDefaults.standard.bool(forKey: "appleHealthAccessRequested")
    @ObservationIgnored private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var today: HealthActivityDay { days.first { Calendar.current.isDateInToday($0.date) } ?? HealthActivityDay(date: .now) }
    var hasData: Bool {
        !weights.isEmpty || heightCM != nil || !workouts.isEmpty
            || days.contains { $0.steps != nil || $0.activeCalories != nil || $0.exerciseMinutes != nil
                || $0.distanceMeters != nil || $0.sleepHours != nil || $0.restingHeartRate != nil
                || $0.averageHeartRate != nil || $0.vo2Max != nil || $0.headphoneAudioMinutes != nil
                || $0.workoutSessions != nil }
    }

    /// 最大摄氧量的健康单位是 ml/(kg·min)。
    nonisolated private static var vo2MaxUnit: HKUnit {
        HKUnit.literUnit(with: .milli)
            .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: HKUnit.minute()))
    }

    /// 需要读取的所有健康数据类型。睡眠和训练是分类/样本类型，单独处理。
    private static var readTypes: Set<HKObjectType> {
        let identifiers: [HKQuantityTypeIdentifier] = [.stepCount, .activeEnergyBurned, .appleExerciseTime,
                                                       .distanceWalkingRunning, .bodyMass, .height,
                                                       .heartRate, .restingHeartRate, .heartRateVariabilitySDNN,
                                                       .vo2Max, .headphoneAudioExposure]
        var types = Set<HKObjectType>(identifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) })
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        types.insert(HKObjectType.workoutType())
        return types
    }

    func connect() async {
        guard isAvailable else { errorMessage = "当前设备无法使用 Apple 健康。"; return }
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
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

    func loadWellnessData(period: WellnessPeriod, document: DiaryDocument, endDate: Date) async throws -> WellnessHealthData {
        guard accessRequested, isAvailable else { return WellnessHealthData() }
        let calendar = Calendar.current
        var earliest: Date?
        if period == .all {
            for identifier in [HKQuantityTypeIdentifier.stepCount, .activeEnergyBurned, .appleExerciseTime,
                               .distanceWalkingRunning, .bodyMass, .height, .heartRate, .restingHeartRate,
                               .heartRateVariabilitySDNN, .vo2Max, .headphoneAudioExposure] {
                try Task.checkCancellation()
                if let date = try await Self.readEarliest(store, type: identifier, end: endDate) {
                    earliest = earliest.map { min($0, date) } ?? date
                }
            }
            if let date = try await Self.readEarliestSleep(store, end: endDate) {
                earliest = earliest.map { min($0, date) } ?? date
            }
            if let date = try await Self.readEarliestWorkout(store, end: endDate) {
                earliest = earliest.map { min($0, date) } ?? date
            }
        }
        let start = period.startDate(document: document, endDate: endDate, earliestHealthDate: earliest, calendar: calendar)
        async let activity = Self.readActivity(store, start: start, end: endDate, calendar: calendar)
        async let measurements = Self.readWeights(store, through: endDate, limit: HKObjectQueryNoLimit)
        async let height = Self.readHeight(store, through: endDate)
        let values = try await (activity, measurements, height)
        try Task.checkCancellation()
        let days = values.0.days.keys.sorted().map { date in
            var day = values.0.days[date] ?? HealthActivityDay(date: date)
            day.date = date
            return day
        }
        return WellnessHealthData(days: days, weights: values.1, heightCM: values.2?.value,
            heightDate: values.2?.date, earliestDate: earliest, workouts: values.0.workouts)
    }

    private func loadSnapshot() async throws {
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -6, to: today) else { return }
        async let activity = Self.readActivity(store, start: start, end: now, calendar: calendar)
        async let measurements = Self.readWeights(store)
        async let height = Self.readHeight(store)
        let values = try await (activity, measurements, height)
        days = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return values.0.days[date] ?? HealthActivityDay(date: date)
        }
        workouts = values.0.workouts
        weights = values.1
        heightCM = values.2?.value
        heightDate = values.2?.date
        lastRefresh = now
    }

    private struct ActivityResult {
        var days: [Date: HealthActivityDay] = [:]
        var workouts: [HealthWorkout] = []
    }

    nonisolated private static func readActivity(_ store: HKHealthStore, start: Date, end: Date,
                                                 calendar: Calendar) async throws -> ActivityResult {
        async let steps = readDaily(store, type: .stepCount, unit: .count(), start: start, end: end, calendar: calendar)
        async let calories = readDaily(store, type: .activeEnergyBurned, unit: .kilocalorie(), start: start, end: end, calendar: calendar)
        async let minutes = readDaily(store, type: .appleExerciseTime, unit: .minute(), start: start, end: end, calendar: calendar)
        async let distance = readDaily(store, type: .distanceWalkingRunning, unit: .meter(), start: start, end: end, calendar: calendar)
        async let heartRate = readDiscreteDaily(store, type: .heartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: start, end: end, calendar: calendar)
        async let restingHeartRate = readDiscreteDaily(store, type: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: start, end: end, calendar: calendar)
        async let hrv = readDiscreteDaily(store, type: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: start, end: end, calendar: calendar)
        async let vo2Max = readDiscreteDaily(store, type: .vo2Max, unit: Self.vo2MaxUnit, start: start, end: end, calendar: calendar)
        async let sleep = readSleep(store, start: start, end: end, calendar: calendar)
        async let audio = readAudioExposure(store, start: start, end: end, calendar: calendar)
        async let workouts = readWorkouts(store, start: start, end: end, calendar: calendar)
        let values = try await (steps, calories, minutes, distance, heartRate, restingHeartRate,
                                hrv, vo2Max, sleep, audio, workouts)
        var days: [Date: HealthActivityDay] = [:]
        for (date, value) in values.0 { merge(&days, date, \.steps, value) }
        for (date, value) in values.1 { merge(&days, date, \.activeCalories, value) }
        for (date, value) in values.2 { merge(&days, date, \.exerciseMinutes, value) }
        for (date, value) in values.3 { merge(&days, date, \.distanceMeters, value) }
        for (date, value) in values.4 { merge(&days, date, \.averageHeartRate, value) }
        for (date, value) in values.5 { merge(&days, date, \.restingHeartRate, value) }
        for (date, value) in values.6 { merge(&days, date, \.heartRateVariabilityMS, value) }
        for (date, value) in values.7 { merge(&days, date, \.vo2Max, value) }
        for (date, value) in values.8 { merge(&days, date, \.sleepHours, value) }
        for (date, value) in values.9 { merge(&days, date, \.headphoneAudioMinutes, value) }
        for (date, totals) in HealthWorkoutSummary.dailyTotals(values.10, calendar: calendar) {
            var day = days[date] ?? HealthActivityDay(date: date)
            day.workoutSessions = totals.sessions
            day.workoutMinutes = totals.minutes
            day.workoutCalories = totals.calories
            days[date] = day
        }
        let sortedWorkouts = values.10.sorted { $0.date > $1.date }
        return ActivityResult(days: days, workouts: sortedWorkouts)
    }

    nonisolated private static func merge(_ days: inout [Date: HealthActivityDay], _ date: Date,
                                          _ keyPath: WritableKeyPath<HealthActivityDay, Double?>, _ value: Double) {
        var day = days[date] ?? HealthActivityDay(date: date)
        day[keyPath: keyPath] = value
        days[date] = day
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

    /// 心率、静息心率、HRV、最大摄氧量这类离散数据取每日平均。
    nonisolated private static func readDiscreteDaily(_ store: HKHealthStore, type identifier: HKQuantityTypeIdentifier,
                                                      unit: HKUnit, start: Date, end: Date,
                                                      calendar: Calendar) async throws -> [Date: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [:] }
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                options: .discreteAverage, anchorDate: start, intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { query, collection, error in
                defer { store.stop(query) }
                if let error { continuation.resume(throwing: error); return }
                var values: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    if let quantity = statistics.averageQuantity() {
                        let value = quantity.doubleValue(for: unit)
                        if value.isFinite && value > 0 { values[calendar.startOfDay(for: statistics.startDate)] = value }
                    }
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    /// 按「醒来那天」汇总真正睡着的时长，忽略卧床时间。
    nonisolated private static func readSleep(_ store: HKHealthStore, start: Date, end: Date,
                                              calendar: Calendar) async throws -> [Date: Double] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [:] }
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                                        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                        HKCategoryValueSleepAnalysis.asleepREM.rawValue]
                var values: [Date: Double] = [:]
                for case let sample as HKCategorySample in samples ?? []
                where asleep.contains(sample.value) {
                    let hours = sample.endDate.timeIntervalSince(sample.startDate) / 3600
                    guard hours.isFinite, hours > 0, hours < 24 else { continue }
                    let day = calendar.startOfDay(for: sample.endDate)
                    values[day, default: 0] += hours
                }
                continuation.resume(returning: values.mapValues { min($0, 24) })
            }
            store.execute(query)
        }
    }

    /// 耳机音量暴露：按天累加戴耳机听音频的时长（分钟）。
    nonisolated private static func readAudioExposure(_ store: HKHealthStore, start: Date, end: Date,
                                                      calendar: Calendar) async throws -> [Date: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: .headphoneAudioExposure) else { return [:] }
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                var values: [Date: Double] = [:]
                for case let sample as HKQuantitySample in samples ?? [] {
                    let minutes = sample.endDate.timeIntervalSince(sample.startDate) / 60
                    guard minutes.isFinite, minutes > 0, minutes < 24 * 60 else { continue }
                    let day = calendar.startOfDay(for: sample.endDate)
                    values[day, default: 0] += minutes
                }
                continuation.resume(returning: values.mapValues { min($0, 24 * 60) })
            }
            store.execute(query)
        }
    }

    nonisolated private static func readWorkouts(_ store: HKHealthStore, start: Date, end: Date,
                                                 calendar: Calendar) async throws -> [HealthWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate,
                limit: 200, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let workouts = (samples as? [HKWorkout] ?? []).compactMap { workout -> HealthWorkout? in
                    let minutes = Int((workout.duration / 60).rounded())
                    guard minutes > 0 else { return nil }
                    let mapping = Self.mapping(for: workout.workoutActivityType)
                    let energy = workout.statistics(for: HKQuantityType(HKQuantityTypeIdentifier.activeEnergyBurned))?
                        .sumQuantity()?.doubleValue(for: .kilocalorie())
                    let heartRate = workout.statistics(for: HKQuantityType(HKQuantityTypeIdentifier.heartRate))?
                        .averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    let distance = Self.distance(of: workout)
                    let record = HealthWorkout(id: workout.uuid, date: workout.startDate, kind: mapping.kind,
                        title: mapping.title, durationMinutes: min(minutes, 600),
                        activeCalories: energy, averageHeartRate: heartRate,
                        distanceMeters: distance)
                    return (try? record.validate()) == nil ? nil : record
                }
                continuation.resume(returning: workouts)
            }
            store.execute(query)
        }
    }

    nonisolated private static func distance(of workout: HKWorkout) -> Double? {
        let types: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming,
                                                 .distanceRowing, .distanceWheelchair]
        for identifier in types {
            guard let type = HKObjectType.quantityType(forIdentifier: identifier),
                  let quantity = workout.statistics(for: type)?.sumQuantity() else { continue }
            let meters = quantity.doubleValue(for: .meter())
            if meters > 0 { return meters }
        }
        return nil
    }

    nonisolated private static func mapping(for type: HKWorkoutActivityType) -> (kind: WorkoutKind, title: String) {
        switch type {
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining, .crossTraining:
            return (.strength, "力量训练")
        case .running: return (.cardio, "跑步")
        case .walking: return (.cardio, "步行")
        case .cycling: return (.cardio, "骑行")
        case .swimming: return (.cardio, "游泳")
        case .rowing: return (.cardio, "划船")
        case .hiking: return (.cardio, "徒步")
        case .elliptical: return (.cardio, "椭圆机")
        case .stairClimbing, .stairs: return (.cardio, "爬楼")
        case .jumpRope: return (.cardio, "跳绳")
        case .highIntensityIntervalTraining: return (.cardio, "高强度间歇")
        case .yoga: return (.cardio, "瑜伽")
        case .pilates: return (.cardio, "普拉提")
        case .dance, .cardioDance: return (.cardio, "舞蹈")
        case .basketball, .soccer, .tennis, .badminton, .tableTennis, .volleyball:
            return (.cardio, "球类运动")
        case .mindAndBody: return (.cardio, "身心训练")
        default: return (.cardio, "其他训练")
        }
    }

    nonisolated private static func readWeights(_ store: HKHealthStore, through end: Date? = nil,
                                                limit: Int = 500) async throws -> [WeightRecord] {
        guard let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = end.map { HKQuery.predicateForSamples(withStart: nil, end: $0, options: .strictEndDate) }
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit,
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

    nonisolated private static func readEarliest(_ store: HKHealthStore, type identifier: HKQuantityTypeIdentifier,
                                                 end: Date) async throws -> Date? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: nil, end: end, options: .strictEndDate)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples?.first?.startDate) }
            }
            store.execute(query)
        }
    }

    nonisolated private static func readEarliestSleep(_ store: HKHealthStore, end: Date) async throws -> Date? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: nil, end: end, options: .strictEndDate)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples?.first?.startDate) }
            }
            store.execute(query)
        }
    }

    nonisolated private static func readEarliestWorkout(_ store: HKHealthStore, end: Date) async throws -> Date? {
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: nil, end: end, options: .strictEndDate)
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples?.first?.startDate) }
            }
            store.execute(query)
        }
    }

    nonisolated private static func readHeight(_ store: HKHealthStore, through end: Date? = nil) async throws -> (value: Double, date: Date)? {
        guard let type = HKObjectType.quantityType(forIdentifier: .height) else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = end.map { HKQuery.predicateForSamples(withStart: nil, end: $0, options: .strictEndDate) }
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1,
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
