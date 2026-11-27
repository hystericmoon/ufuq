import SwiftUI
import UfuqCore

/// The tiles of the open panel, in reading and Tab order.
enum BentoTileID: String, CaseIterable, Identifiable {
    case prayer, ai, agents, actions, nowPlaying, battery

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
    var actions: [GitHubBuild] = []

    var smallTiles: [BentoTileID] {
        (agents.isEmpty ? [] : [.agents]) + (actions.isEmpty ? [] : [.actions]) + (battery == nil ? [] : [.battery])
    }
    var tileOrder: [BentoTileID] { [.prayer, .ai] + smallTiles }
}

/// Where the pointer is relative to the body. `x` is points from the body's centre.
struct JellyPointer: Equatable {
    var hovering = false
    var x: CGFloat = 0
    var pressed = false
}

/// A file being dragged toward the notch. `distance` is points from the screen's top edge;
/// `x` is points from the body's centre. The neck shows under 160 pt, the drop zone under 60 pt.
struct FileDragState: Equatable {
    var distance: CGFloat
    var x: CGFloat
    var overDropZone: Bool { distance < 60 }
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
    @Published var actions: [GitHubBuild] = []
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
    /// A file drag near the top edge of this display; nil when none (written by the tray code).
    @Published var fileDrag: FileDragState?
    /// Bumped each time the tray swallows a drop, so the body can bulge.
    @Published var swallowToken = 0
    /// The tray's items, mirrored for the views that animate around them.
    @Published var tray: [TrayItem] = []

    // MARK: Phase 7 contract (set in the main session; each field has one writer)

    /// Pointer over the body. Writer: motion layer (NotchController hover tracking).
    @Published var pointer = JellyPointer()
    /// A file drag near the top edge, nil otherwise. Writer: File Tray. Reader: motion (the neck).
    @Published var fileDrag: FileDragState?
    /// Bumped once per accepted drop. Writer: File Tray. Reader: motion (the swallow bulge).
    @Published var swallowToken = 0
    /// Tray contents, in order. Writer: File Tray.
    @Published var tray: [TrayItem] = []
    /// Current track, nil when nothing is playing or the module is unavailable. Writer: Now Playing.
    @Published var nowPlaying: NowPlaying?

    var content: BentoContent { BentoContent(snapshot: snapshot, now: now, ai: ai, battery: battery, agents: agents, actions: actions) }

    var onEscape: () -> Void = {}
    var onTapCollapsed: () -> Void = {}
}
