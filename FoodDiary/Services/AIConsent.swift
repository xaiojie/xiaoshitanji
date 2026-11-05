import Foundation
import Observation

/// Each screen waits here before sending analysis content to the AI service.
@MainActor
@Observable
final class AIConsent {
    static let storageKey = "ai.dataSharingConsentVersion"
    static let currentVersion = 1

    var isPresented = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isAuthorized: Bool {
        defaults.integer(forKey: Self.storageKey) == Self.currentVersion
    }

    func requirePermission() async throws {
        try Task.checkCancellation()
        if isAuthorized { return }
        let id = UUID()
        let approved = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                waiters[id] = continuation
                isPresented = true
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
        try Task.checkCancellation()
        guard approved, isAuthorized else { throw CancellationError() }
    }

    func approve() {
        guard !waiters.isEmpty else { return }
        defaults.set(Self.currentVersion, forKey: Self.storageKey)
        resolve(true)
    }

    func decline() { resolve(false) }
    func cancelPending() { resolve(false) }

    private func cancel(_ id: UUID) {
        let waiter = waiters.removeValue(forKey: id)
        if waiters.isEmpty { isPresented = false }
        waiter?.resume(returning: false)
    }

    private func resolve(_ approved: Bool) {
        let pending = Array(waiters.values)
        waiters.removeAll()
        isPresented = false
        for waiter in pending { waiter.resume(returning: approved) }
    }
}
