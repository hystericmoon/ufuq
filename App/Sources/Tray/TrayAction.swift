import Foundation
import UfuqCore
import UniformTypeIdentifiers

/// One thing you can do with a tray item; the context menu, the keyboard and VoiceOver share the list.
enum TrayAction: String, CaseIterable, Identifiable {
    case open, reveal, share, airdrop, zip, png, jpeg, heic, rename, pinFolder, remove

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: return "Open"
        case .reveal: return "Reveal in Finder"
        case .share: return "Share…"
        case .airdrop: return "AirDrop"
        case .zip: return "Zip"
        case .png: return "Convert to PNG"
        case .jpeg: return "Convert to JPEG"
        case .heic: return "Convert to HEIC"
        case .rename: return "Rename…"
        case .pinFolder: return "Pin Folder"
        case .remove: return "Remove from Tray"
        }
    }

    /// Single-letter keyboard action while an item has focus (Return opens, Delete removes).
    var key: Character? {
        switch self {
        case .reveal: return "r"
        case .share: return "s"
        case .airdrop: return "a"
        case .zip: return "z"
        case .png: return "p"
        case .jpeg: return "j"
        case .heic: return "h"
        case .rename: return "n"
        case .pinFolder: return "f"
        case .open, .remove: return nil
        }
    }

    static func forKey(_ character: Character) -> TrayAction? {
        let lower = Character(character.lowercased())
        return allCases.first { $0.key == lower }
    }

    static func isImage(_ item: TrayItem) -> Bool {
        guard item.kind == .file else { return false }
        let ext = (item.path as NSString).pathExtension
        return UTType(filenameExtension: ext)?.conforms(to: .image) ?? false
    }

    /// The actions that make sense for this item, in menu order.
    static func available(for item: TrayItem) -> [TrayAction] {
        var list: [TrayAction] = [.open, .reveal, .share, .airdrop, .zip]
        if isImage(item) { list += [.png, .jpeg, .heic] }
        list.append(.rename)
        if item.kind == .folder { list.append(.pinFolder) }
        list.append(.remove)
        return list
    }

    var imageFormat: ImageFormat? {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        default: return nil
        }
    }
}
