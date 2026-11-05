import Foundation

@main struct AIConsentRegression {
    @MainActor static func main() async throws {
        let suite = "AIConsentRegression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = AIConsent(defaults: defaults)
        var operations = 0
        let first = Task { @MainActor in
            try await consent.requirePermission()
            operations += 1
        }
        await Task.yield()
        precondition(consent.isPresented && operations == 0, "Analysis started before explicit consent")
        consent.approve()
        try await first.value
        precondition(operations == 1 && consent.isAuthorized && !consent.isPresented)
        try await AIConsent(defaults: defaults).requirePermission()
        print("PASS — first request waits for explicit approval; approved permission persists")

        defaults.removeObject(forKey: AIConsent.storageKey)
        let declined = Task { @MainActor in
            try await consent.requirePermission()
            operations += 1
        }
        await Task.yield()
        precondition(consent.isPresented)
        consent.decline()
        do { try await declined.value; fatalError("Declined analysis continued") }
        catch is CancellationError {}
        precondition(operations == 1 && !consent.isAuthorized)
        print("PASS — declining blocks analysis and revocation requires a new approval")

        let cancelled = Task { @MainActor in
            try await consent.requirePermission()
            operations += 1
        }
        await Task.yield()
        cancelled.cancel()
        do { try await cancelled.value; fatalError("Cancelled analysis continued") }
        catch is CancellationError {}
        precondition(operations == 1 && !consent.isPresented && !consent.isAuthorized)
        print("PASS — task cancellation dismisses the prompt and never grants permission")

        let dismissed = Task { @MainActor in try await consent.requirePermission() }
        await Task.yield()
        consent.cancelPending()
        do { try await dismissed.value; fatalError("Dismissed analysis continued") }
        catch is CancellationError {}
        precondition(!consent.isPresented && !consent.isAuthorized)
        print("PASS — leaving the view resolves pending authorization without sending")

        let cancelledPeer = Task { @MainActor in try await consent.requirePermission() }
        let remainingPeer = Task { @MainActor in try await consent.requirePermission() }
        await Task.yield()
        cancelledPeer.cancel()
        do { try await cancelledPeer.value; fatalError("Cancelled peer continued") }
        catch is CancellationError {}
        precondition(consent.isPresented)
        consent.approve()
        try await remainingPeer.value
        precondition(consent.isAuthorized && !consent.isPresented)
        print("PASS — cancelling one waiting task preserves the other request")
    }
}
