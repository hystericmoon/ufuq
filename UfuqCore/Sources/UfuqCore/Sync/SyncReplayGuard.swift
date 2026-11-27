import Foundation

/// Remembers every auth token accepted within its validity window and refuses a second use.
/// Clients seal a fresh token per request (AES-GCM, random nonce), so a repeat is a replay
/// captured on the same network. Entries expire with the token's own skew window.
public actor SyncReplayGuard {
    private var seen: [String: Date] = [:]
    private let capacity: Int

    public init(capacity: Int = 4096) {
        self.capacity = capacity
    }

    /// Records `token` and returns true on its first use; false if it was already used and has not expired.
    public func admit(_ token: String, expires: Date, now: Date) -> Bool {
        if let until = seen[token], until >= now { return false }
        if seen.count >= capacity { seen = seen.filter { $0.value >= now } }
        // Still full of live tokens: drop the soonest to expire (these are stale tokens from honest clients).
        if seen.count >= capacity, let soonest = seen.min(by: { $0.value < $1.value })?.key {
            seen[soonest] = nil
        }
        seen[token] = expires
        return true
    }

    public var count: Int { seen.count }
}
