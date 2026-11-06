import CoreLocation
import Foundation
import NutritionCore
import Observation
import UIKit
import UserNotifications

@MainActor
@Observable
final class RunTrackingModel: NSObject, CLLocationManagerDelegate {
    private(set) var session: RunSession?
    private(set) var records: [RunRecord] = []
    private(set) var location: RunLocation?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var preciseLocation = false
    private(set) var recovered = false
    private(set) var archiveError: String?
    private(set) var archiveWarning: String?
    private(set) var pendingRemovals: [UUID] = []
    var errorMessage: String?
    private(set) var locationWarning: String?
    var goalNotice = false
    var heartRates: [RunHeartRatePoint] = []
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let archive: RunArchive
    @ObservationIgnored private var backgroundActivity: CLBackgroundActivitySession?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastWrite = Date.distantPast
    @ObservationIgnored private var preparing = false

    init(directory: URL = URL.documentsDirectory.appending(path: "FoodDiary/Runs")) {
        archive = RunArchive(directory: directory)
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
        preciseLocation = manager.accuracyAuthorization == .fullAccuracy
        reloadArchive()
    }

    func reloadArchive() {
        guard !isTracking else { return }
        archiveError = nil
        archiveWarning = nil
        do {
            let snapshot = try archive.loadRecords()
            records = snapshot.records
            if !snapshot.unreadableFiles.isEmpty {
                archiveWarning = "\(snapshot.unreadableFiles.count) 条路线文件暂时无法读取，原文件已保留，其他记录仍可使用。"
            }
        } catch {
            archiveWarning = "历史路线暂时无法读取，原文件已保留。\(error.localizedDescription)"
        }
        do {
            session = try archive.loadDraft()
            if session?.state == .running {
                session?.recover()
                recovered = true
                if let session { try archive.saveDraft(session) }
            }
            if let session, let stored = records.first(where: { $0.id == session.id }) {
                heartRates = stored.heartRates
            }
        } catch {
            archiveError = "跑步草稿暂时无法读取，原文件已保留。\(error.localizedDescription)"
        }
        do { pendingRemovals = try archive.pendingDeletions() }
        catch { archiveWarning = "待清理列表暂时无法读取，请稍后重试。原文件已保留。" }
    }

    func preserveUnreadableDraft() throws {
        _ = try archive.preserveUnreadableDraft()
        session = nil
        heartRates = []
        reloadArchive()
    }

    var pendingRecord: RunRecord? {
        guard let session else { return nil }
        var record = records.first { $0.id == session.id } ?? RunRecord(session: session)
        record.session = session
        if !heartRates.isEmpty { record.heartRates = heartRates }
        return record
    }

    func beginRemoval(id: UUID) throws {
        try archive.markForDeletion(id: id)
        if !pendingRemovals.contains(id) { pendingRemovals.append(id) }
    }

    func retryRemovals(diary: DiaryModel) throws {
        for id in pendingRemovals {
            if let workout = diary.document.workouts.first(where: { $0.id == id }) {
                try diary.deleteWorkout(workout)
            }
            try remove(id: id)
            if session?.id == id { try discard() }
        }
    }

    var isTracking: Bool { session?.state == .running }
    var locationAllowed: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }
    var gpsReady: Bool {
        locationAllowed && preciseLocation && (location.map {
            $0.isValid && Date.now.timeIntervalSince($0.timestamp) <= 15
        } ?? false)
    }

    var locationMessage: String {
        if !CLLocationManager.locationServicesEnabled() { return "系统定位已关闭，可到系统设置开启。" }
        if authorization == .denied || authorization == .restricted { return "请在系统设置允许定位，也可选择仅计时。" }
        if !locationAllowed { return "开始前需要允许定位。" }
        if !preciseLocation { return "GPS 跑步需要精确位置，可点下方开启。" }
        return gpsReady ? "GPS 已就绪" : "正在寻找准确位置，建议到室外稍等。"
    }

    func prepare() {
        guard session == nil else { return }
        preparing = true
        errorMessage = nil
        locationWarning = nil
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if locationAllowed {
            if !preciseLocation {
                manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "RunTracking")
            }
            manager.startUpdatingLocation()
        }
    }

    func stopPreparing() {
        preparing = false
        if !isTracking { manager.stopUpdatingLocation() }
    }

    func start(targetMeters: Double?, usesGPS: Bool) throws {
        guard archiveError == nil, session == nil else {
            throw DiaryError.invalidInput("请先处理已有跑步草稿或文件读取提示。")
        }
        guard !usesGPS || gpsReady else { throw DiaryError.invalidInput(locationMessage) }
        guard usesGPS || targetMeters == nil else {
            throw DiaryError.invalidInput("目标跑需要 GPS 距离，请开启定位。")
        }
        let next = RunSession(targetMeters: targetMeters, usesGPS: usesGPS)
        try archive.saveDraft(next)
        session = next
        heartRates = []
        recovered = false
        goalNotice = false
        errorMessage = nil
        locationWarning = nil
        beginUpdates()
    }

    func requestGoalNotifications() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    func pause() {
        session?.pause(at: .now)
        stopUpdates()
        persist()
    }

    func resume() {
        guard session?.state == .paused else { return }
        session?.resume(at: .now)
        recovered = false
        beginUpdates()
        persist()
    }

    func finish() {
        session?.finish(at: .now)
        stopUpdates()
        persist()
    }

    func checkpoint() {
        guard session != nil else { return }
        session?.checkpoint(at: .now)
        persist()
    }

    @discardableResult
    func save(_ record: RunRecord, preservingDetails: Bool = true) throws -> RunRecord {
        let record = try archive.save(record, preservingDetails: preservingDetails)
        records.removeAll { $0.id == record.id }
        records.append(record)
        records.sort { $0.session.startedAt > $1.session.startedAt }
        return record
    }

    /// 先保存 RunRecord、再提交 WorkoutRecord，最后清草稿；重试保持相同 ID。
    func completeSave() throws {
        try archive.clearDraft()
        stopUpdates()
        session = nil
        heartRates = []
        recovered = false
    }

    func discard() throws {
        try archive.clearDraft()
        stopUpdates()
        session = nil
        heartRates = []
        errorMessage = nil
        recovered = false
    }

    func remove(id: UUID) throws {
        try archive.finishDeletion(id: id)
        records.removeAll { $0.id == id }
        pendingRemovals.removeAll { $0 == id }
    }

    private func beginUpdates() {
        preparing = false
        stopUpdates()
        if session?.usesGPS == true {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            backgroundActivity = CLBackgroundActivitySession()
            manager.startUpdatingLocation()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isTracking else { return }
                self.session?.checkpoint(at: .now)
                if Date.now.timeIntervalSince(self.lastWrite) >= 5 { self.persist() }
            }
        }
    }

    private func stopUpdates() {
        timer?.invalidate()
        timer = nil
        manager.stopUpdatingLocation()
        backgroundActivity?.invalidate()
        backgroundActivity = nil
        manager.allowsBackgroundLocationUpdates = false
    }

    private func persist() {
        guard let session else { return }
        do {
            try archive.saveDraft(session)
            lastWrite = .now
        } catch {
            errorMessage = "本次草稿暂未写入，请保留页面并重试。\(error.localizedDescription)"
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let precise = manager.accuracyAuthorization == .fullAccuracy
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorization = status
            self.preciseLocation = precise
            if self.locationAllowed {
                if self.preparing || self.isTracking { self.manager.startUpdatingLocation() }
            } else if self.isTracking && self.session?.usesGPS == true {
                self.session?.breakTrack()
                self.locationWarning = "定位权限已变更，轨迹暂时中断，计时仍在进行。"
                self.persist()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let values = locations.map {
            RunLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                        timestamp: $0.timestamp, horizontalAccuracy: $0.horizontalAccuracy)
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for value in values {
                if value.isValid {
                    self.location = value
                    self.locationWarning = nil
                }
                if self.session?.usesGPS == true, self.preciseLocation,
                   self.session?.ingest(value, receivedAt: .now) == true {
                    self.goalNotice = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    if UIApplication.shared.applicationState != .active, let session = self.session {
                        let content = UNMutableNotificationContent()
                        content.title = "奶蛙提醒 · 目标完成"
                        content.body = "已经完成设定里程，可以继续跑，也可以打开应用暂停和结束。"
                        content.sound = .default
                        let request = UNNotificationRequest(identifier: "run-goal-\(session.id)", content: content, trigger: nil)
                        Task { try? await UNUserNotificationCenter.current().add(request) }
                    }
                }
            }
            if self.isTracking { self.persist() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.session?.breakTrack()
            self.locationWarning = denied ? "定位不可用，请检查系统权限。" : "GPS 信号暂时中断，已保留此前轨迹。"
            self.persist()
        }
    }
}
