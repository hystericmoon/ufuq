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

/// One display's island: its own panel and view model; content is shared through the controller.
@MainActor
private final class ScreenIsland {
    let displayID: CGDirectDisplayID
    let panel: NotchPanel
    let hostingView: NotchHostingView
    let model = NotchModel()
    var metrics: ScreenMetrics
    var shrinkTask: Task<Void, Never>?

    init(displayID: CGDirectDisplayID, metrics: ScreenMetrics) {
        self.displayID = displayID
        self.metrics = metrics
        panel = NotchPanel(contentRect: NotchGeometry.windowFrame(for: .collapsed, metrics: metrics))
        hostingView = NotchHostingView(rootView: NotchRootView(model: model))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
    }

    func close() {
        shrinkTask?.cancel()
        panel.orderOut(nil)
        panel.close()
    }
}

/// Owns the panels (one per display, or only the notch display), the state machine, the arbiter
/// and the peek queue. Every island shows the same wings and peeks; the expanded panel opens on
/// one display only: the one with the pointer for the hotkey, the touched one for click or hover.
@MainActor
final class NotchController: NSObject {
    let registry: ModuleRegistry

    private var machine = NotchStateMachine()
    private var arbiter = ActivityArbiter()
    private var queue = PeekQueue()

    private var islands: [ScreenIsland] = []
    /// The display the expanded panel uses.
    private var activeID: CGDirectDisplayID?
    private var hotkey: Hotkey?
    private var timer: Timer?
    private var peekTasks: [Task<Void, Never>] = []
    private var screenObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var clickMonitor: Any?

    private var layout = WingLayout()
    private var snapshot: PrayerSnapshot?
    private var focusedTile: BentoTileID = .prayer

    private var previousApp: NSRunningApplication?
    private var lastAnnouncedPeekID: String?
    private var lastEscape = Date.distantPast
    private var tickCount = 0
    private var allDisplays = AppSettings.allDisplays

    init(registry: ModuleRegistry) {
        self.registry = registry
        super.init()
    }

    // MARK: - Start

    func start() {
        rebuildIslands()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildIslands() }
        }
        // The "every display" setting can change while running.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.allDisplays != AppSettings.allDisplays else { return }
                self.allDisplays = AppSettings.allDisplays
                self.rebuildIslands()
            }
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
        if machine.isExpanded {
            machine.collapse()
        } else {
            activeID = pointerDisplayID() ?? islands.first?.displayID
            machine.open(origin: .hotkey)
        }
        applyState(restoreFocus: true)
    }

    // MARK: - Events

    private func open(origin: ExpandOrigin, on displayID: CGDirectDisplayID) {
        activeID = displayID
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

    private func pointerEntered(_ displayID: CGDirectDisplayID) {
        queue.setHovering(true, at: Date())
        if !machine.isExpanded { activeID = displayID }
        machine.mouseEntered(hoverEnabled: AppSettings.hoverEnabled)
        applyState(restoreFocus: false)
    }

    private func pointerExited(_ displayID: CGDirectDisplayID) {
        queue.setHovering(false, at: Date())
        // Leaving a collapsed island on another display must not close the open panel.
        guard displayID == activeID || !machine.isExpanded else { return }
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

        let newLayout = arbiter.layout(for: registry.activities(at: now), at: now)
        if newLayout != layout { layout = newLayout }
        if machine.isExpanded {
            snapshot = (registry.module(id: "prayer") as? PrayerModule)?.snapshot(at: now)
        }
        for island in islands {
            if island.model.layout != layout { island.model.layout = layout }
            island.model.now = now
            if island.displayID == activeID, machine.isExpanded {
                island.model.snapshot = snapshot
                updateAIRows(island, now: now)
                // The battery moves slowly; a reading every 30 s keeps the tile honest.
                if tickCount % 30 == 0 { refreshBattery(island) }
            }
        }
        applyState(restoreFocus: false)

        tickCount += 1
        if tickCount % 60 == 0 {
            Task { [weak self] in await self?.registry.refreshAll() }
        }
    }

    // MARK: - State to windows

    private var activeIsland: ScreenIsland? {
        islands.first { $0.displayID == activeID } ?? islands.first
    }

    private func applyState(restoreFocus: Bool) {
        let wasExpanded = islands.contains { $0.model.state.kind == .expanded }
        if machine.isExpanded, activeIsland?.displayID != activeID { activeID = activeIsland?.displayID }

        for island in islands {
            let newState = NotchState.shown(machine.state, onActiveDisplay: island.displayID == activeID, peek: machine.currentPeek)
            let oldState = island.model.state
            guard newState != oldState else { continue }
            if oldState.kind != newState.kind {
                if newState.kind == .expanded {
                    snapshot = (registry.module(id: "prayer") as? PrayerModule)?.snapshot(at: Date())
                    island.model.snapshot = snapshot
                    updateAIRows(island, now: Date())
                    island.model.battery = BatteryReader.read()
                    island.model.focusedTile = focusedTile
                }
                updateFrame(island, for: newState.kind)
            }
            if oldState.kind == .expanded { focusedTile = island.model.focusedTile }
            island.model.state = newState
        }

        let isExpanded = islands.contains { $0.model.state.kind == .expanded }
        if isExpanded, !wasExpanded {
            becameExpanded()
        } else if wasExpanded, !isExpanded {
            leftExpanded(restoreFocus: restoreFocus)
        }
    }

    /// Rows for the AI tile from the module's last refresh; assigned only when they changed.
    private func updateAIRows(_ island: ScreenIsland, now: Date) {
        guard let module = registry.module(id: "ai") as? AIUsageModule else { return }
        let rows = AIUsageRows.rows(from: module.lines(at: now), now: now)
        if island.model.ai != rows { island.model.ai = rows }
    }

    private func becameExpanded() {
        guard machine.origin != .hover, let island = activeIsland else { return }
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        NSApp.activate(ignoringOtherApps: true)
        island.panel.makeKeyAndOrderFront(nil)
        island.panel.makeFirstResponder(island.hostingView)
        island.model.focusToken += 1
        // Give SwiftUI a moment to lay out, then tell VoiceOver where focus is.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak island] in
            MainActor.assumeIsolated {
                guard let self, let island, self.machine.isExpanded else { return }
                island.model.focusToken += 1
                NSAccessibility.post(element: island.panel as Any, notification: .focusedUIElementChanged)
            }
        }
    }

    private func leftExpanded(restoreFocus: Bool) {
        let wasKey = islands.contains { $0.panel.isKeyWindow }
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
        // One announcement, however many displays show the peek.
        lastAnnouncedPeekID = event.id
        var userInfo: [NSAccessibility.NotificationUserInfoKey: Any] = [.announcement: event.announcement]
        let priority: NSAccessibilityPriorityLevel = event.priority == .critical ? .high : .medium
        userInfo[.priority] = priority.rawValue
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: userInfo)
    }

    // MARK: - Screens

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    private static func metrics(of screen: NSScreen) -> ScreenMetrics {
        ScreenMetrics(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxLeftWidth: screen.auxiliaryTopLeftArea?.width ?? 0,
            auxRightWidth: screen.auxiliaryTopRightArea?.width ?? 0)
    }

    /// Every display, or (setting off) the notch display, else the main one.
    private func chosenScreens() -> [NSScreen] {
        if allDisplays { return NSScreen.screens }
        let one = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
        return one.map { [$0] } ?? []
    }

    private func pointerDisplayID() -> CGDirectDisplayID? {
        let point = NSEvent.mouseLocation
        let ids = Set(islands.map(\.displayID))
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            .flatMap(Self.displayID(of:))
            .flatMap { ids.contains($0) ? $0 : nil }
    }

    /// Adds, keeps or removes islands to match the displays; keeps state on displays that stay.
    private func rebuildIslands() {
        var kept: [ScreenIsland] = []
        for screen in chosenScreens() {
            guard let id = Self.displayID(of: screen) else { continue }
            let metrics = Self.metrics(of: screen)
            if let existing = islands.first(where: { $0.displayID == id }) {
                existing.metrics = metrics
                kept.append(existing)
            } else {
                kept.append(makeIsland(id: id, metrics: metrics))
            }
        }
        for old in islands where !kept.contains(where: { $0 === old }) { old.close() }
        islands = kept
        if let activeID, !islands.contains(where: { $0.displayID == activeID }) { self.activeID = nil }
        for island in islands {
            island.model.layout = layout
            applyMetrics(island)
            island.shrinkTask?.cancel()
            island.panel.setFrame(
                NotchGeometry.windowFrame(
                    for: island.model.state.kind, metrics: island.metrics,
                    smallTiles: island.model.content.smallTiles.count),
                display: true)
            island.panel.orderFrontRegardless()
        }
        applyState(restoreFocus: false)
    }

    private func makeIsland(id: CGDirectDisplayID, metrics: ScreenMetrics) -> ScreenIsland {
        let island = ScreenIsland(displayID: id, metrics: metrics)
        island.model.onEscape = { [weak self] in self?.handleEscape() }
        island.model.onTapCollapsed = { [weak self] in self?.open(origin: .click, on: id) }
        island.panel.onCancel = { [weak self] in self?.handleEscape() }
        island.hostingView.onMouseEntered = { [weak self] in self?.pointerEntered(id) }
        island.hostingView.onMouseExited = { [weak self] in self?.pointerExited(id) }
        return island
    }

    private func applyMetrics(_ island: ScreenIsland) {
        let m = island.metrics
        island.model.topInset = m.hasNotch ? m.safeAreaTop : 0
        island.model.centerGap = m.hasNotch ? NotchGeometry.notchWidth(m) : 16
        island.model.stripHeight = NotchGeometry.stripHeight(m)
        island.model.shapeSize = NotchGeometry.size(
            for: island.model.state.kind, metrics: m, smallTiles: island.model.content.smallTiles.count)
    }

    /// A battery appearing or going away changes the open panel's width.
    private func refreshBattery(_ island: ScreenIsland) {
        let battery = BatteryReader.read()
        guard battery != island.model.battery else { return }
        let resized = (battery == nil) != (island.model.battery == nil)
        island.model.battery = battery
        if resized { updateFrame(island, for: island.model.state.kind) }
    }

    /// Grow the window first, then let the shape morph; on shrink wait for the morph to finish.
    private func updateFrame(_ island: ScreenIsland, for kind: NotchState.Kind) {
        applyMetrics(island)
        let smallTiles = island.model.content.smallTiles.count
        island.model.shapeSize = NotchGeometry.size(for: kind, metrics: island.metrics, smallTiles: smallTiles)
        let target = NotchGeometry.windowFrame(for: kind, metrics: island.metrics, smallTiles: smallTiles)
        let current = island.panel.frame
        island.shrinkTask?.cancel()
        let shrinking = target.width < current.width || target.height < current.height
        if shrinking {
            island.shrinkTask = Task { [weak island] in
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled, let island else { return }
                island.panel.setFrame(target, display: true)
            }
        } else {
            island.panel.setFrame(target, display: true)
        }
    }
}
