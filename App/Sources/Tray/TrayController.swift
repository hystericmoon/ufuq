import AppKit
import SwiftUI
import UfuqCore
import UniformTypeIdentifiers

/// The tray's state and actions, shared by every island and the floating tray. The notch
/// controller wires the callbacks and mirrors the result into each island's `NotchModel`.
@MainActor
final class TrayController: ObservableObject {
    static let shared = TrayController()

    @Published private(set) var items: [TrayItem] = []
    @Published private(set) var pinned: [String] = []
    /// A file drag is in progress near the notch or over the open panel.
    @Published var dragActive = false { didSet { rowShownMaybeChanged() } }
    /// The keyboard path (⌥⇧T, Services) asked for the row even when it is empty.
    @Published var revealed = false { didSet { rowShownMaybeChanged() } }
    /// The next focus request goes to the tray row instead of a tile.
    @Published var wantsFocus = false
    @Published var dropTargeted = false
    @Published var errorText: String?
    @Published var statusText: String?
    @Published var renamingID: UUID?
    @Published var renameText = ""

    /// The row below the tiles shows when there is something in it, or something is coming.
    var isRowShown: Bool { !items.isEmpty || dragActive || revealed }

    var onRowShownChanged: () -> Void = {}
    /// `swallowed` is true when items were just added.
    var onItemsChanged: (_ swallowed: Bool) -> Void = { _ in }
    var onRequestOpen: () -> Void = {}

    private let store: TrayStore
    private var lastRowShown = false
    private var errorTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?

    init(store: TrayStore = TrayStore()) {
        self.store = store
        store.load()
        items = store.items
        pinned = store.pinnedFolders
        lastRowShown = isRowShown
    }

    // MARK: - Adding

    /// Adds files (de-duplicated by path), saves, and tells VoiceOver. Returns how many were new.
    @discardableResult
    func add(urls: [URL]) -> Int {
        var added: [TrayItem] = []
        for url in urls where url.isFileURL {
            let url = url.standardizedFileURL
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            let isDirectory = values?.isDirectory ?? false
            let item = TrayItem(
                path: url.path, name: url.lastPathComponent,
                size: isDirectory ? nil : values?.fileSize,
                kind: isDirectory ? .folder : .file)
            if store.add(item) { added.append(item) }
        }
        guard !added.isEmpty else { return 0 }
        sync()
        let message = added.count == 1 ? "Added \(added[0].name) to tray" : "Added \(added.count) items to tray"
        announce(message)
        onItemsChanged(true)
        return added.count
    }

    /// Loads the file URLs of dropped providers off the main thread, then adds them in order.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let typeID = UTType.fileURL.identifier
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(typeID) }
        guard !fileProviders.isEmpty else { return false }
        let lock = NSLock()
        var results = [URL?](repeating: nil, count: fileProviders.count)
        let group = DispatchGroup()
        for (index, provider) in fileProviders.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: typeID, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let value = item as? URL {
                    url = value
                }
                lock.lock()
                results[index] = url
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.add(urls: results.compactMap { $0 })
                self.dropTargeted = false
            }
        }
        return true
    }

    // MARK: - Removing and pinning

    func remove(_ item: TrayItem) {
        store.remove(id: item.id)
        sync()
        onItemsChanged(false)
    }

    func clear() {
        store.clear()
        sync()
        announce("Tray cleared")
        onItemsChanged(false)
    }

    func pin(_ item: TrayItem) {
        guard item.kind == .folder else { return }
        if store.pin(folder: item.path) { sync() }
    }

    func unpin(_ path: String) {
        store.unpin(folder: path)
        sync()
    }

    func openPinned(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    // MARK: - Actions

    func perform(_ action: TrayAction, on item: TrayItem) {
        guard FileManager.default.fileExists(atPath: item.path) else {
            fail("\(item.name) is no longer there")
            return
        }
        let url = item.url
        switch action {
        case .open:
            NSWorkspace.shared.open(url)
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .share:
            share(url)
        case .airdrop:
            if let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: [url]) {
                service.perform(withItems: [url])
            } else {
                fail("AirDrop is not available")
            }
        case .zip:
            run(TrayActions().zip(item.path))
        case .png, .jpeg, .heic:
            if let format = action.imageFormat { run(TrayActions().convertImage(item.path, to: format)) }
        case .compressVideo:
            compressVideo(item.url)
        case .makePDF:
            combinePDF(anchoredAt: item.url)
        case .ocrText:
            ocrImage(item.url)
        case .removeBackground:
            removeBackground(item.url)
        case .transcribe:
            transcribeAudio(item.url)
        case .rename:
            renameText = item.name
            renamingID = item.id
        case .pinFolder:
            pin(item)
        case .remove:
            remove(item)
        }
    }

    var canCombineTrayToPDF: Bool {
        pdfCompatibleURLs.count >= 2
    }

    private var pdfCompatibleURLs: [URL] {
        items.filter { TrayAction.isImage($0) || TrayAction.isPDF($0) }.map(\.url)
    }

    func combineTrayToPDF() {
        let urls = pdfCompatibleURLs
        guard !urls.isEmpty else {
            fail("Add images or PDFs to combine")
            return
        }
        runCombinePDF(urls: urls)
    }

    func captureScreenOCR() {
        setStatus("Select text area…", clearAfter: nil)
        Task { [weak self] in
            let outcome = await VisionServices.captureScreenAndOCR()
            guard let self else { return }
            guard let outcome else {
                self.statusText = nil
                return
            }
            switch outcome {
            case .success(let lines):
                self.finishOCR(lines: lines)
            case .failure(let error):
                self.statusText = nil
                self.fail(error.localizedDescription)
            }
        }
    }

    private func compressVideo(_ url: URL) {
        setStatus("Compressing video…", clearAfter: nil)
        Task { [weak self] in
            do {
                let output = try await MediaTransformer.compressVideo(at: url)
                guard let self else { return }
                self.setStatus("Video compressed", clearAfter: 3)
                self.add(urls: [output])
            } catch {
                self?.statusText = nil
                self?.fail(error.localizedDescription)
            }
        }
    }

    private func combinePDF(anchoredAt url: URL) {
        let trayPDFInputs = pdfCompatibleURLs
        let urls = trayPDFInputs.count >= 2 ? trayPDFInputs : [url]
        runCombinePDF(urls: urls)
    }

    private func runCombinePDF(urls: [URL]) {
        setStatus("Creating PDF…", clearAfter: nil)
        Task { [weak self] in
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    try MediaTransformer.combineToPDF(urls: urls)
                }.value
                guard let self else { return }
                self.setStatus("PDF created", clearAfter: 3)
                self.add(urls: [output])
            } catch {
                self?.statusText = nil
                self?.fail(error.localizedDescription)
            }
        }
    }

    private func ocrImage(_ url: URL) {
        setStatus("Reading text…", clearAfter: nil)
        Task { [weak self] in
            do {
                let lines = try await VisionServices.recognizeText(at: url)
                self?.finishOCR(lines: lines)
            } catch {
                self?.statusText = nil
                self?.fail(error.localizedDescription)
            }
        }
    }

    private func finishOCR(lines: [String]) {
        let message = TrayActions.formatOCRStatus(lineCount: lines.count)
        guard !lines.isEmpty else {
            setStatus(message, clearAfter: 3)
            announce(message)
            return
        }
        let joined = lines.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(joined, forType: .string)
        setStatus(message, clearAfter: 3)
        announce(message)
    }

    private func removeBackground(_ url: URL) {
        setStatus("Removing background…", clearAfter: nil)
        Task { [weak self] in
            do {
                let output = try await VisionServices.removeBackground(at: url)
                guard let self else { return }
                self.setStatus("Background removed", clearAfter: 3)
                self.add(urls: [output])
            } catch {
                self?.statusText = nil
                self?.fail(error.localizedDescription)
            }
        }
    }

    private func transcribeAudio(_ url: URL) {
        setStatus("Transcribing…", clearAfter: nil)
        Task { [weak self] in
            let outcome = await SpeechTranscriber.shared.transcribeFile(at: url)
            guard let self else { return }
            switch outcome {
            case .success(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let words = trimmed.split(whereSeparator: \.isWhitespace).count
                let msg = TrayActions.formatTranscriptStatus(wordCount: words)
                if words > 0 {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(trimmed, forType: .string)
                }
                self.setStatus(msg, clearAfter: 3)
                self.announce(msg)
            case .failure(let error):
                self.statusText = nil
                self.fail(error.localizedDescription)
            }
        }
    }

    private func setStatus(_ text: String, clearAfter seconds: Double?) {
        errorText = nil
        statusText = text
        statusTask?.cancel()
        guard let seconds else { return }
        statusTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.statusText = nil
        }
    }

    func cancelRename() {
        renamingID = nil
        renameText = ""
    }

    func commitRename(_ item: TrayItem) {
        let newName = renameText
        renamingID = nil
        renameText = ""
        switch TrayActions().rename(item.path, to: newName) {
        case .failure(.unchanged):
            return
        case .failure(let error):
            fail(Self.describe(error))
        case .success(let destination):
            do {
                try FileManager.default.moveItem(atPath: item.path, toPath: destination)
            } catch {
                fail(error.localizedDescription)
                return
            }
            replace(item, with: TrayItem(
                id: item.id, path: destination, name: (destination as NSString).lastPathComponent,
                size: item.size, addedAt: item.addedAt, kind: item.kind))
        }
    }

    /// Swaps an item for an edited copy at the same position.
    private func replace(_ old: TrayItem, with new: TrayItem) {
        guard let index = store.items.firstIndex(where: { $0.id == old.id }) else { return }
        store.remove(id: old.id)
        store.add(new)
        store.move(from: IndexSet(integer: store.items.count - 1), to: index)
        sync()
        onItemsChanged(false)
    }

    private func share(_ url: URL) {
        let window = NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible && $0.contentView != nil }
        guard let view = window?.contentView else {
            fail("Nothing to share from")
            return
        }
        let anchor = NSRect(x: view.bounds.midX, y: view.bounds.maxY - 8, width: 1, height: 1)
        NSSharingServicePicker(items: [url]).show(relativeTo: anchor, of: view, preferredEdge: .minY)
    }

    /// Runs a planned command off the main thread; the result joins the tray, a failure shows in the row.
    private func run(_ command: TrayCommand) {
        Task { [weak self] in
            let failure = await Task.detached(priority: .userInitiated) {
                TrayController.execute(command)
            }.value
            guard let self else { return }
            if let failure {
                self.fail(failure)
            } else {
                self.add(urls: [URL(fileURLWithPath: command.output)])
            }
        }
    }

    nonisolated static func execute(_ command: TrayCommand) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return error.localizedDescription
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return nil }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "\((command.executable as NSString).lastPathComponent) failed" : text
    }

    static func describe(_ error: TrayActionError) -> String {
        switch error {
        case .emptyName: return "The name cannot be empty"
        case .invalidCharacter(let c): return "The name cannot contain \"\(c)\""
        case .leadingColon: return "The name cannot start with a colon"
        case .tooLong: return "The name is too long"
        case .unchanged: return "The name did not change"
        case .destinationExists: return "A file with that name already exists"
        }
    }

    // MARK: - Helpers

    func fail(_ text: String) {
        errorText = text
        announce(text)
        errorTask?.cancel()
        errorTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            self?.errorText = nil
        }
    }

    func clearError() { errorText = nil }

    private func sync() {
        items = store.items
        pinned = store.pinnedFolders
        do {
            try store.save()
        } catch {
            errorText = "Could not save the tray"
        }
        rowShownMaybeChanged()
    }

    private func rowShownMaybeChanged() {
        let now = isRowShown
        guard now != lastRowShown else { return }
        lastRowShown = now
        onRowShownChanged()
    }

    private func announce(_ text: String) {
        let userInfo: [NSAccessibility.NotificationUserInfoKey: Any] = [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ]
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: userInfo)
    }

    /// "PDF document, 1.2 MB" for VoiceOver.
    static func spokenDetail(_ item: TrayItem) -> String {
        guard item.kind == .file else { return "Folder" }
        guard let size = item.size else { return "File" }
        return "File, " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

/// The "Add to Ufuq Tray" Services menu item (`NSServices` in Info.plist, message `addToTray`).
final class TrayServicesProvider: NSObject {
    static let shared = TrayServicesProvider()

    @objc func addToTray(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = pboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else {
            error.pointee = "No files were provided" as NSString
            return
        }
        Task { @MainActor in
            let tray = TrayController.shared
            tray.add(urls: urls)
            tray.onRequestOpen()
        }
    }
}
