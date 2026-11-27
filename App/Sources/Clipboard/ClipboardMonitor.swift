import AppKit
import Foundation
import UfuqCore

@MainActor
final class ClipboardMonitor: ObservableObject {
    static let shared = ClipboardMonitor()

    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var copiedItemID: UUID?

    private var history = ClipboardHistory(maxItems: 30)
    private var timer: Timer?
    private var lastChangeCount: Int
    private var lastWrittenChangeCount: Int?
    private var copiedFlashTask: Task<Void, Never>?

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        stop()
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func copy(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)
        lastWrittenChangeCount = pb.changeCount
        lastChangeCount = pb.changeCount
        copiedItemID = item.id
        copiedFlashTask?.cancel()
        copiedFlashTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            self?.copiedItemID = nil
        }
        if NSWorkspace.shared.isVoiceOverEnabled {
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [.announcement: "Copied to clipboard"]
            )
        }
    }

    func togglePin(_ id: UUID) {
        history.togglePin(id: id)
        items = history.items
    }

    func remove(_ id: UUID) {
        history.remove(id: id)
        items = history.items
    }

    func clearUnpinned() {
        history.clearUnpinned()
        items = history.items
    }

    private func poll() {
        guard AppSettings.clipboardEnabled else { return }
        let pb = NSPasteboard.general
        let current = pb.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        if let written = lastWrittenChangeCount, written == current {
            lastWrittenChangeCount = nil
            return
        }
        let types = pb.types?.map(\.rawValue) ?? []
        guard !ClipboardHistory.shouldIgnore(pasteboardTypes: types) else { return }
        guard let text = pb.string(forType: .string) else { return }
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName
        if history.record(text: text, sourceApp: appName, at: Date()) {
            items = history.items
        }
    }
}
