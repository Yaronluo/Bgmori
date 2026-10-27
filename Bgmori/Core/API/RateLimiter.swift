import Foundation

actor RateLimiter {
    private var nextAllowed = ContinuousClock.now
    private let interval: TimeInterval

    init(interval: TimeInterval) { self.interval = interval }

    /// Claim a slot only when dispatching. Cancelled waiters never reserve future time.
    func wait(maxDelay: TimeInterval = .infinity) async throws {
        let deadline = maxDelay.isFinite ? ContinuousClock.now.advanced(by: .seconds(max(0, maxDelay))) : nil
        while true {
            try Task.checkCancellation()
            let now = ContinuousClock.now
            if nextAllowed <= now {
                nextAllowed = now.advanced(by: .seconds(interval))
                return
            }
            if let deadline, nextAllowed >= deadline { throw URLError(.timedOut) }
            try await Task.sleep(until: nextAllowed, clock: .continuous)
        }
    }
}
