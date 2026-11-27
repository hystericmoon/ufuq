import Foundation
import UfuqCore
import UniformTypeIdentifiers

/// One thing you can do with a tray item; the context menu, the keyboard and VoiceOver share the list.
enum TrayAction: String, CaseIterable, Identifiable {
    case open, reveal, share, airdrop, zip
    case png, jpeg, heic
    case compressVideo, makePDF, ocrText, removeBackground, transcribe
    case rename, pinFolder, remove

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
        case .compressVideo: return "Compress Video"
        case .makePDF: return "Combine to PDF"
        case .ocrText: return "Copy Text (OCR)"
        case .removeBackground: return "Remove Background"
        case .transcribe: return "Transcribe Audio"
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
        case .compressVideo: return "c"
        case .makePDF: return "d"
        case .ocrText: return "o"
        case .removeBackground: return "b"
        case .transcribe: return "t"
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
        if TrayActions.isImageExtension(ext) { return true }
        return UTType(filenameExtension: ext)?.conforms(to: .image) ?? false
    }

    static func isVideo(_ item: TrayItem) -> Bool {
        guard item.kind == .file else { return false }
        let ext = (item.path as NSString).pathExtension
        if TrayActions.isVideoExtension(ext) { return true }
        return UTType(filenameExtension: ext)?.conforms(to: .movie) ?? false
    }

    static func isPDF(_ item: TrayItem) -> Bool {
        guard item.kind == .file else { return false }
        let ext = (item.path as NSString).pathExtension
        return TrayActions.isPDFExtension(ext) || (UTType(filenameExtension: ext)?.conforms(to: .pdf) ?? false)
    }

    static func isAudio(_ item: TrayItem) -> Bool {
        guard item.kind == .file else { return false }
        let ext = (item.path as NSString).pathExtension
        return TrayActions.isAudioExtension(ext) || (UTType(filenameExtension: ext)?.conforms(to: .audio) ?? false)
    }

    /// The actions that make sense for this item, in menu order.
    static func available(for item: TrayItem) -> [TrayAction] {
        var list: [TrayAction] = [.open, .reveal, .share, .airdrop, .zip]
        if isImage(item) {
            list += [.png, .jpeg, .heic, .ocrText, .removeBackground, .makePDF]
        } else if isVideo(item) {
            list.append(.compressVideo)
        } else if isPDF(item) {
            list.append(.makePDF)
        } else if isAudio(item) {
            list.append(.transcribe)
        }
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
