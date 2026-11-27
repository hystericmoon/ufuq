import AppKit
import SwiftUI
import UfuqCore

/// Hosting view that reports the pointer entering and leaving the panel (for optional hover).
final class NotchHostingView: NSHostingView<NotchRootView> {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseExited?()
    }
}

/// Owns the panel, the state machine, the arbiter and the peek queue.
@MainActor
final class NotchController: NSObject {
    let registry: ModuleRegistry
    let model = NotchModel()

    private var machine = NotchStateMachine()
    private var arbiter = ActivityArbiter()
    private var queue = PeekQueue()

    private var panel: NotchPanel!
    private var hostingView: NotchHostingView!
    private var hotkey: Hotkey?
    private var timer: Timer?
    private var peekTasks: [Task<Void, Never>] = []
    private var shrinkTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var clickMonitor: Any?

    private var previousApp: NSRunningApplication?
    private var lastAnnouncedPeekID: String?
    private var lastEscape = Date.distantPast
    private var tickCount = 0

    init(registry: ModuleRegistry) {
        self.registry = registry
        super.init()
    }

    // MARK: - Start

    func start() {
        model.onEscape = { [weak self] in self?.handleEscape() }
        model.onTapCollapsed = { [weak self] in self?.open(origin: .click) }

        let metrics = currentMetrics()
        let frame = NotchGeometry.windowFrame(for: .collapsed, metrics: metrics)
        panel = NotchPanel(contentRect: frame)
        panel.onCancel = { [weak self] in self?.handleEscape() }

        hostingView = NotchHostingView(rootView: NotchRootView(model: model))
        hostingView.sizingOptions = []
        hostingView.onMouseEntered = { [weak self] in self?.pointerEntered() }
        hostingView.onMouseExited = { [weak self] in self?.pointerExited() }
        panel.contentView = hostingView

        applyMetrics(metrics)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedOutside() }
        }

        hotkey = Hotkey { [weak self] in
            MainActor.assumeIsolated { self?.toggleExpanded() }
        }
        if hotkey == nil { NSLog("Ufuq: could not register the Option+Space hotkey") }

        for module in registry.enabledModules {
            let stream = module.peekEvents()
            peekTasks.append(Task { [weak self] in
                for await event in stream {
                    self?.enqueuePeek(event)
                }
            })
        }

        Task { [weak self] in
            await self?.registry.refreshAll()
            self?.tick()
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    // MARK: - Public actions

    func toggleExpanded() {
        let wasExpanded = machine.isExpanded
        if wasExpanded {
            machine.collapse()
        } else {
            machine.open(origin: .hotkey)
        }
        applyState(restoreFocus: true)
    }

    // MARK: - Events

    private func open(origin: ExpandOrigin) {
        machine.open(origin: origin)
        applyState(restoreFocus: false)
    }

    private func handleEscape() {
        // The panel and the SwiftUI view can both report the same key press.
        let now = Date()
        guard now.timeIntervalSince(lastEscape) > 0.15 else { return }
        lastEscape = now

        switch machine.escape() {
        case .ignored:
            break
        case .collapsed:
            applyState(restoreFocus: true)
        case .dismissedPeek:
            queue.dismissCurrent(at: now)
            machine.setPeek(queue.current)
            announceIfNew()
            applyState(restoreFocus: false)
        }
    }

    private func pointerEntered() {
        queue.setHovering(true, at: Date())
        machine.mouseEntered(hoverEnabled: AppSettings.hoverEnabled)
        applyState(restoreFocus: false)
    }

    private func pointerExited() {
        queue.setHovering(false, at: Date())
        machine.mouseExited()
        applyState(restoreFocus: false)
    }

    private func clickedOutside() {
        guard machine.isExpanded else { return }
        machine.collapse()
        applyState(restoreFocus: false)
    }

    private func enqueuePeek(_ event: PeekEvent) {
        SyncService.shared.publish(event)
        queue.enqueue(event, at: Date())
        machine.setPeek(queue.current)
        announceIfNew()
        applyState(restoreFocus: false)
    }

    // MARK: - Tick

    private func tick() {
        let now = Date()
        queue.tick(at: now)
        machine.setPeek(queue.current)
        announceIfNew()

        let layout = arbiter.layout(for: registry.activities(at: now), at: now)
        if layout != model.layout { model.layout = layout }
        model.now = now
        if machine.isExpanded {
            model.snapshot = (registry.module(id: "prayer") as? PrayerModule)?.snapshot(at: now)
        }
        applyState(restoreFocus: false)

        tickCount += 1
        if tickCount % 60 == 0 {
            Task { [weak self] in await self?.registry.refreshAll() }
        }
    }

    // MARK: - State to window

    private func applyState(restoreFocus: Bool) {
        let newState = machine.state
        let oldState = model.state
        guard newState != oldState else { return }

        let oldKind = oldState.kind
        let newKind = newState.kind
        if oldKind != newKind {
            if newKind == .expanded {
                model.snapshot = (registry.module(id: "prayer") as? PrayerModule)?.snapshot(at: Date())
            }
            updateFrame(for: newKind)
        }
        model.state = newState

        if newKind == .expanded, oldKind != .expanded {
            becameExpanded()
        } else if oldKind == .expanded, newKind != .expanded {
            leftExpanded(restoreFocus: restoreFocus)
        }
    }

    private func becameExpanded() {
        guard machine.origin != .hover else { return }
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(hostingView)
        model.focusToken += 1
        // Give SwiftUI a moment to lay out, then tell VoiceOver where focus is.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.machine.isExpanded else { return }
                self.model.focusToken += 1
                NSAccessibility.post(element: self.panel as Any, notification: .focusedUIElementChanged)
            }
        }
    }

    private func leftExpanded(restoreFocus: Bool) {
        let wasKey = panel.isKeyWindow
        if restoreFocus || wasKey {
            if let app = previousApp {
                app.activate(options: [])
            } else {
                NSApp.deactivate()
            }
        }
        previousApp = nil
    }

    private func announceIfNew() {
        guard let event = queue.current, event.id != lastAnnouncedPeekID else {
            if queue.current == nil { lastAnnouncedPeekID = nil }
            return
        }
        lastAnnouncedPeekID = event.id
        var userInfo: [NSAccessibility.NotificationUserInfoKey: Any] = [.announcement: event.announcement]
        let priority: NSAccessibilityPriorityLevel = event.priority == .critical ? .high : .medium
        userInfo[.priority] = priority.rawValue
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: userInfo)
    }

    // MARK: - Screens

    private func chooseScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func currentMetrics() -> ScreenMetrics {
        guard let screen = chooseScreen() else {
            let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
            return ScreenMetrics(frame: frame, visibleFrame: frame, safeAreaTop: 0, auxLeftWidth: 0, auxRightWidth: 0)
        }
        return ScreenMetrics(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxLeftWidth: screen.auxiliaryTopLeftArea?.width ?? 0,
            auxRightWidth: screen.auxiliaryTopRightArea?.width ?? 0)
    }

    private func applyMetrics(_ metrics: ScreenMetrics) {
        model.topInset = metrics.hasNotch ? metrics.safeAreaTop : 0
        model.centerGap = metrics.hasNotch ? NotchGeometry.notchWidth(metrics) : 16
        model.shapeSize = NotchGeometry.size(for: model.state.kind, metrics: metrics)
    }

    private func reposition() {
        let metrics = currentMetrics()
        applyMetrics(metrics)
        shrinkTask?.cancel()
        panel.setFrame(NotchGeometry.windowFrame(for: model.state.kind, metrics: metrics), display: true)
    }

    /// Grow the window first, then let the shape morph; on shrink wait for the morph to finish.
    private func updateFrame(for kind: NotchState.Kind) {
        let metrics = currentMetrics()
        applyMetrics(metrics)
        model.shapeSize = NotchGeometry.size(for: kind, metrics: metrics)
        let target = NotchGeometry.windowFrame(for: kind, metrics: metrics)
        let current = panel.frame
        shrinkTask?.cancel()
        let shrinking = target.width < current.width || target.height < current.height
        if shrinking {
            shrinkTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled, let self else { return }
                self.panel.setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }
}
