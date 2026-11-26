import Foundation

/// A notch module (Prayer, AI usage, Agent status, …), UI-free.
///
/// The Mac app refines this with a SwiftUI protocol that adds `expandedView()` and
/// `settingsView()`; keeping views out of here lets `swift test` run on Linux.
///
/// Methods that touch a data source `throw` instead of crashing. `ModuleRegistry` catches the
/// error and reports the module as `.unavailable`.
public protocol UfuqModule: AnyObject {
    var id: String { get }
    var title: String { get }
    var isEnabled: Bool { get set }
    var status: ModuleStatus { get }

    /// Reloads data from the source.
    func refresh() async throws
    /// What to show in the collapsed notch, or nil for nothing.
    func collapsedActivity(at now: Date) throws -> LiveActivity?
    /// Peek alerts as they happen.
    func peekEvents() -> AsyncStream<PeekEvent>
    /// One-sentence spoken summary for VoiceOver.
    func accessibilitySummary() -> String
}

public extension UfuqModule {
    func refresh() async throws {}

    func peekEvents() -> AsyncStream<PeekEvent> {
        AsyncStream { $0.finish() }
    }
}
