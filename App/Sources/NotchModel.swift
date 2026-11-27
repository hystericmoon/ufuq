import SwiftUI
import UfuqCore

/// The tiles of the open panel, in reading and Tab order.
enum BentoTileID: String, CaseIterable, Identifiable {
    case prayer, ai, agents, battery

    var id: String { rawValue }
}

/// One AI usage line: an account or a provider with its worst window.
struct AIUsageRow: Equatable, Identifiable {
    var id: String
    var provider: UsageProvider
    var name: String
    var fraction: Double
    /// e.g. "Week 41% · resets in 2 h 10 min".
    var detail: String
    var isBetaSource = false
    /// Non-nil for a Claude token-count row: tokens in the current 5-hour block, no percent.
    var tokens: Int? = nil
    /// The source could not be read; the row shows a dash.
    var isUnavailable = false
    /// Spoken value for VoiceOver; empty falls back to `detail`.
    var accessibilityValue = ""
}

/// What the open panel shows. A small tile appears only while its module has something live.
struct BentoContent: Equatable {
    var snapshot: PrayerSnapshot?
    var now = Date()
    var ai: [AIUsageRow] = []
    var battery: BatteryStatus?
    var agents: [AgentSession] = []

    var smallTiles: [BentoTileID] {
        (agents.isEmpty ? [] : [.agents]) + (battery == nil ? [] : [.battery])
    }
    var tileOrder: [BentoTileID] { [.prayer, .ai] + smallTiles }
}

/// What the SwiftUI views observe. The controller writes it; views never write state directly.
@MainActor
final class NotchModel: ObservableObject {
    @Published var state: NotchState = .collapsed
    @Published var layout = WingLayout()
    @Published var snapshot: PrayerSnapshot?
    @Published var now = Date()
    @Published var ai: [AIUsageRow] = []
    @Published var battery: BatteryStatus?
    @Published var agents: [AgentSession] = []
    /// The tile that gets focus when the panel opens (the last one used).
    @Published var focusedTile: BentoTileID = .prayer
    /// Height of the black strip on top of the open panel.
    @Published var stripHeight: CGFloat = 32
    /// Size of the black shape for the current state.
    @Published var shapeSize = NotchGeometry.collapsedSize
    /// Height of the camera housing the content must stay below; 0 on screens without a notch.
    @Published var topInset: CGFloat = 0
    /// Space between the wings: the camera housing, or a small gap on the floating pill.
    @Published var centerGap: CGFloat = 16
    /// Bumped each time the panel opens, so the expanded view moves keyboard and VoiceOver focus in.
    @Published var focusToken = 0

    var content: BentoContent { BentoContent(snapshot: snapshot, now: now, ai: ai, battery: battery, agents: agents) }

    var onEscape: () -> Void = {}
    var onTapCollapsed: () -> Void = {}
}
