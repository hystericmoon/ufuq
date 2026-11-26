import SwiftUI
import UfuqCore

enum ExpandedTab: String, CaseIterable, Identifiable {
    case prayer = "Prayer"
    case ai = "AI usage"

    var id: String { rawValue }
}

/// What the SwiftUI views observe. The controller writes it; views never write state directly.
@MainActor
final class NotchModel: ObservableObject {
    @Published var state: NotchState = .collapsed
    @Published var layout = WingLayout()
    @Published var snapshot: PrayerSnapshot?
    @Published var now = Date()
    @Published var selectedTab: ExpandedTab = .prayer
    /// Size of the black shape for the current state.
    @Published var shapeSize = NotchGeometry.collapsedSize
    /// Height of the camera housing the content must stay below; 0 on screens without a notch.
    @Published var topInset: CGFloat = 0
    /// Space between the wings: the camera housing, or a small gap on the floating pill.
    @Published var centerGap: CGFloat = 16
    /// Bumped each time the panel opens, so the expanded view moves keyboard and VoiceOver focus in.
    @Published var focusToken = 0

    var onEscape: () -> Void = {}
    var onTapCollapsed: () -> Void = {}
}
