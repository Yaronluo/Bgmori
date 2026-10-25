import Foundation

actor RateLimiter {
    private var nextAllowed = Date.distantPast
    private let interval: TimeInterval

    init(interval: TimeInterval) {
        self.interval = interval
    }

    func wait() async {
        let now = Date()
        let allowed = max(now, nextAllowed)
        nextAllowed = allowed.addingTimeInterval(interval)
        let delay = allowed.timeIntervalSince(now)
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
}
