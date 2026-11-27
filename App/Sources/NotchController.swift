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
    private var trayHotkey: Hotkey?
    private var trayDrag: TrayDragMonitor?
    private var floatingTray: FloatingTrayController?

    private var layout = WingLayout()
    private var snapshot: PrayerSnapshot?
    private var focusedTile: BentoTileID = .prayer

    private var previousApp: NSRunningApplication?
    private var lastAnnouncedPeekID: String?
    private var lastEscape = Date.distantPast
    private var tickCount = 0
    private var lastGitHubPoll = Date.distantPast
    private var lastNowPlayingPoll = Date.distantPast
    private var nowPlayingPausedSince: Date?
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
        startTray()

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
        // Agent state files are tiny; read them every second (peeks flow through the module's stream).
        if let agent = registry.module(id: "agent") {
            Task { try? await agent.refresh() }
        }
        pollGitHub(at: now)
        pollNowPlaying(at: now)
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
                refreshAgents(island, now: now)
                refreshActions(island, now: now)
                refreshNowPlaying(island)
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
                    island.model.agents = (registry.module(id: "agent") as? AgentStatusModule)?.sessions(at: Date()) ?? []
                    island.model.actions = githubBuilds(at: Date())
                    island.model.battery = BatteryReader.read()
                    refreshNowPlaying(island)
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

    /// A first or last session appearing changes the open panel's width.
    private func refreshAgents(_ island: ScreenIsland, now: Date) {
        guard let module = registry.module(id: "agent") as? AgentStatusModule else { return }
        let sessions = module.sessions(at: now)
        guard sessions != island.model.agents else { return }
        let resized = sessions.isEmpty != island.model.agents.isEmpty
        island.model.agents = sessions
        if resized { updateFrame(island, for: island.model.state.kind) }
    }

    /// The GitHub module polls on its own schedule: 15 s while a build runs, else 60 s.
    private func pollGitHub(at now: Date) {
        guard let module = registry.module(id: "github") as? GitHubActionsModule else { return }
        guard now.timeIntervalSince(lastGitHubPoll) >= module.pollInterval(at: now) else { return }
        lastGitHubPoll = now
        Task { try? await module.refresh() }
    }

    /// Now Playing polls every 2 s while something plays, every 5 s otherwise.
    private func pollNowPlaying(at now: Date) {
        guard let module = registry.module(id: "nowPlaying") as? NowPlayingModule, module.isEnabled else { return }
        let interval: TimeInterval = module.nowPlaying?.isPlaying == true ? 2 : 5
        guard now.timeIntervalSince(lastNowPlayingPoll) >= interval else { return }
        lastNowPlayingPoll = now
        Task { try? await module.refresh() }
    }

    /// Copies the module's state into the model. A track appearing or leaving changes the panel width.
    private func refreshNowPlaying(_ island: ScreenIsland) {
        guard let module = registry.module(id: "nowPlaying") as? NowPlayingModule else { return }
        let track = module.nowPlaying
        let now = Date()
        if let track, !track.isPlaying {
            if nowPlayingPausedSince == nil { nowPlayingPausedSince = now }
        } else {
            nowPlayingPausedSince = nil
        }
        let before = island.model.content.showsNowPlaying
        if island.model.nowPlaying != track { island.model.nowPlaying = track }
        if island.model.nowPlayingPausedSince != nowPlayingPausedSince {
            island.model.nowPlayingPausedSince = nowPlayingPausedSince
        }
        if before != island.model.content.showsNowPlaying { updateFrame(island, for: island.model.state.kind) }
    }

    private func githubBuilds(at now: Date) -> [GitHubBuild] {
        guard let module = registry.module(id: "github") as? GitHubActionsModule,
              module.status.isAvailable else { return [] }
        return module.builds(at: now)
    }

    /// A first or last build appearing changes the open panel's width.
    private func refreshActions(_ island: ScreenIsland, now: Date) {
        let builds = githubBuilds(at: now)
        guard builds != island.model.actions else { return }
        let resized = builds.isEmpty != island.model.actions.isEmpty
        island.model.actions = builds
        if resized { updateFrame(island, for: island.model.state.kind) }
    }

    private func becameExpanded() {
        // A drag-opened panel must not take focus from the app the drag comes from.
        guard machine.origin != .hover, machine.origin != .drag, let island = activeIsland else { return }
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
                    smallTiles: island.model.content.smallTiles.count,
                    trayRow: TrayController.shared.isRowShown),
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
            for: island.model.state.kind, metrics: m, smallTiles: island.model.content.smallTiles.count,
            trayRow: TrayController.shared.isRowShown)
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
        let trayRow = TrayController.shared.isRowShown
        island.model.shapeSize = NotchGeometry.size(for: kind, metrics: island.metrics, smallTiles: smallTiles, trayRow: trayRow)
        let target = NotchGeometry.windowFrame(for: kind, metrics: island.metrics, smallTiles: smallTiles, trayRow: trayRow)
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

// MARK: - File tray

extension NotchController {
    /// Wires the tray: ⌥⇧T, the Services item, drag monitoring and the shake tray.
    fileprivate func startTray() {
        let tray = TrayController.shared
        tray.onRowShownChanged = { [weak self] in self?.resizeForTray() }
        tray.onItemsChanged = { [weak self] swallowed in self?.publishTray(swallowed: swallowed) }
        tray.onRequestOpen = { [weak self] in self?.openTray() }
        publishTray(swallowed: false)
        NSApp.servicesProvider = TrayServicesProvider.shared

        trayHotkey = Hotkey(keyCode: Hotkey.trayKeyCode, modifiers: Hotkey.trayModifiers, id: 2) { [weak self] in
            MainActor.assumeIsolated { self?.openTray() }
        }
        if trayHotkey == nil { NSLog("Ufuq: could not register the Option+Shift+T hotkey") }

        let floating = FloatingTrayController(tray: tray)
        floatingTray = floating
        let monitor = TrayDragMonitor()
        monitor.onFileDrag = { [weak self] point in self?.trayDragMoved(to: point) }
        monitor.onShake = { [weak self] point in self?.floatingTray?.show(at: point) }
        monitor.onDragEnded = { [weak self] in self?.trayDragEnded() }
        monitor.start()
        trayDrag = monitor
    }

    /// ⌥⇧T and the Services item: open the panel with focus on the tray row.
    fileprivate func openTray() {
        let tray = TrayController.shared
        tray.revealed = true
        tray.wantsFocus = true
        if machine.isExpanded {
            activeIsland?.model.focusToken += 1
        } else {
            activeID = pointerDisplayID() ?? islands.first?.displayID
            machine.open(origin: .hotkey)
            applyState(restoreFocus: true)
        }
    }

    /// The row appeared or went away: the open panel changes height.
    fileprivate func resizeForTray() {
        for island in islands where island.model.state.kind == .expanded {
            updateFrame(island, for: .expanded)
        }
    }

    /// Mirrors the tray into every island's model; a drop also bumps the swallow token.
    fileprivate func publishTray(swallowed: Bool) {
        let items = TrayController.shared.items
        for island in islands {
            island.model.tray = items
            if swallowed { island.model.swallowToken += 1 }
        }
    }

    /// A file drag moved. The island under the pointer gets `fileDrag`; the drop zone opens the panel.
    /// Coordinates: `NSEvent.mouseLocation` and `NSScreen.frame` share the screen space (origin
    /// bottom-left); x is made relative to the collapsed body's centre.
    fileprivate func trayDragMoved(to point: NSPoint) {
        let tray = TrayController.shared
        var current: FileDragState?
        var currentID: CGDirectDisplayID?
        for island in islands {
            guard let screen = NSScreen.screens.first(where: { Self.displayID(of: $0) == island.displayID }),
                  NSMouseInRect(point, screen.frame, false) || point.y >= screen.frame.maxY
                    && point.x >= screen.frame.minX && point.x <= screen.frame.maxX else { continue }
            let midX = NotchGeometry.windowFrame(for: .collapsed, metrics: island.metrics).midX
            current = FileDragState.make(pointer: point, screenFrame: screen.frame, bodyMidX: midX)
            currentID = island.displayID
            break
        }
        for island in islands {
            let value = island.displayID == currentID ? current : nil
            if island.model.fileDrag != value { island.model.fileDrag = value }
        }

        if let current, current.overDropZone, let currentID {
            tray.dragActive = true
            if !machine.isExpanded {
                activeID = currentID
                machine.dragEntered()
                applyState(restoreFocus: false)
            }
        } else if machine.isExpanded, machine.origin == .drag {
            let inside = activeIsland?.panel.frame.insetBy(dx: -12, dy: -12).contains(point) ?? false
            if !inside {
                tray.dragActive = false
                machine.dragLeft(hasItems: !tray.items.isEmpty)
                applyState(restoreFocus: false)
            }
        }
    }

    /// The drag ended (dropped or not). A short delay lets an accepted drop finish loading first.
    fileprivate func trayDragEnded() {
        for island in islands where island.model.fileDrag != nil { island.model.fileDrag = nil }
        floatingTray?.dragEnded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let tray = TrayController.shared
                tray.dragActive = false
                tray.dropTargeted = false
                self.machine.dragLeft(hasItems: !tray.items.isEmpty)
                self.applyState(restoreFocus: false)
            }
        }
    }
}
