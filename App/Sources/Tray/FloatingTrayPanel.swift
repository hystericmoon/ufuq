import AppKit
import SwiftUI

/// The small tray that buds off at the pointer when you shake a file drag. Black, radius 22,
/// accepts drops like the open panel; closes on Esc, on a click outside, or 1.5 s after the
/// drag ends while it is empty.
final class FloatingTrayPanel: NSPanel {
    static let size = CGSize(width: 220, height: 140)
    var onCancel: (() -> Void)?

    init(tray: TrayController) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        title = "Ufuq tray"
        setAccessibilityLabel("Ufuq tray")
        let host = NSHostingView(rootView: FloatingTrayView(tray: tray))
        host.frame = NSRect(origin: .zero, size: Self.size)
        contentView = host
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

private struct FloatingTrayView: View {
    @ObservedObject var tray: TrayController
    @FocusState private var focus: UUID?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.peek, style: .continuous)
        ScrollView {
            if tray.items.isEmpty {
                Text("Drop files here")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .accessibilityLabel("Tray, empty. Drop files here")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 0)], spacing: 4) {
                    ForEach(tray.items) { item in
                        TrayItemView(item: item, tray: tray, focus: $focus)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: FloatingTrayPanel.size.width, height: FloatingTrayPanel.size.height)
        .background(shape.fill(Tokens.notchBg))
        .overlay(
            shape.strokeBorder(
                Tokens.textSecondary,
                style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .padding(4)
                .opacity(tray.items.isEmpty || tray.dropTargeted ? 1 : 0))
        .environment(\.colorScheme, .dark)
        .trayDrop(tray)
    }
}

/// Opens, positions and closes the floating tray.
@MainActor
final class FloatingTrayController {
    private let tray: TrayController
    private var panel: FloatingTrayPanel?
    private var clickMonitor: Any?
    private var closeTask: Task<Void, Never>?

    init(tray: TrayController) { self.tray = tray }

    var isShown: Bool { panel?.isVisible == true }

    /// Shows the tray centred on `point` (AppKit screen coordinates), kept inside the screen.
    func show(at point: NSPoint) {
        closeTask?.cancel()
        let panel = self.panel ?? FloatingTrayPanel(tray: tray)
        panel.onCancel = { [weak self] in self?.close() }
        self.panel = panel
        var origin = NSPoint(x: point.x - FloatingTrayPanel.size.width / 2,
                             y: point.y - FloatingTrayPanel.size.height / 2)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main {
            let area = screen.visibleFrame
            origin.x = min(max(origin.x, area.minX), area.maxX - FloatingTrayPanel.size.width)
            origin.y = min(max(origin.y, area.minY), area.maxY - FloatingTrayPanel.size.height)
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        panel.makeKey()
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let panel = self.panel, panel.isVisible else { return }
                    if !panel.frame.contains(NSEvent.mouseLocation) { self.close() }
                }
            }
        }
    }

    /// The drag ended: an empty floating tray goes away after 1.5 s.
    func dragEnded() {
        guard isShown else { return }
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.tray.items.isEmpty { self.close() }
        }
    }

    func close() {
        closeTask?.cancel()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        panel?.orderOut(nil)
    }
}
