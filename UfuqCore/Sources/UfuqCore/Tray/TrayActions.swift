import Foundation

/// A command for the Mac app to run; Core never runs anything.
public struct TrayCommand: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    /// Where the command writes its result.
    public var output: String

    public init(executable: String, arguments: [String], output: String) {
        self.executable = executable
        self.arguments = arguments
        self.output = output
    }
}

public enum TrayActionError: Error, Equatable, Sendable {
    case emptyName
    case invalidCharacter(Character)
    case leadingColon
    case tooLong
    case unchanged
    case destinationExists(String)
}

public enum ImageFormat: String, CaseIterable, Sendable {
    case png, jpeg, heic, tiff

    /// File extension for the output.
    public var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
}

/// Pure planners for tray actions. Reveal and AirDrop are UI-only and not here.
public struct TrayActions {
    public var fileExists: (String) -> Bool

    public init(fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.fileExists = fileExists
    }

    /// `ditto -c -k --sequesterRsrc --keepParent <src> <dst.zip>`, next to the source.
    public func zip(_ source: String) -> TrayCommand {
        let stem = (source as NSString).lastPathComponent
        let dir = (source as NSString).deletingLastPathComponent
        let destination = uniquePath(directory: dir, stem: stem, ext: "zip")
        return TrayCommand(
            executable: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", source, destination],
            output: destination)
    }

    /// Zips several items into one archive named "Archive.zip" (ditto takes one source, so the
    /// app should stage them in a folder first); this plans the unique name only.
    public func archivePath(in directory: String) -> String {
        uniquePath(directory: directory, stem: "Archive", ext: "zip")
    }

    /// New full path after renaming `path` to `newName`, or why the name is not allowed.
    public func rename(_ path: String, to newName: String) -> Result<String, TrayActionError> {
        if let error = Self.validate(name: newName) { return .failure(error) }
        let dir = (path as NSString).deletingLastPathComponent
        if newName == (path as NSString).lastPathComponent { return .failure(.unchanged) }
        let destination = (dir as NSString).appendingPathComponent(newName)
        if fileExists(destination) { return .failure(.destinationExists(destination)) }
        return .success(destination)
    }

    public static func validate(name: String) -> TrayActionError? {
        if name.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty { return .emptyName }
        if name.contains("/") { return .invalidCharacter("/") }
        if name.hasPrefix(":") { return .leadingColon }
        if name.contains("\0") { return .invalidCharacter("\0") }
        if name.utf8.count > 255 { return .tooLong }
        return nil
    }

    /// `sips -s format <fmt> <src> --out <dst>` with a unique destination next to the source.
    public func convertImage(_ source: String, to format: ImageFormat) -> TrayCommand {
        let stem = ((source as NSString).lastPathComponent as NSString).deletingPathExtension
        let dir = (source as NSString).deletingLastPathComponent
        let destination = uniquePath(directory: dir, stem: stem, ext: format.fileExtension)
        return TrayCommand(
            executable: "/usr/bin/sips",
            arguments: ["-s", "format", format.rawValue, source, "--out", destination],
            output: destination)
    }

    /// Unique output path for a compressed `.mp4` next to the source video.
    public func compressVideoOutput(_ source: String) -> String {
        let stem = ((source as NSString).lastPathComponent as NSString).deletingPathExtension
        let dir = (source as NSString).deletingLastPathComponent
        return uniquePath(directory: dir, stem: "\(stem) compressed", ext: "mp4")
    }

    /// Unique output path for combining images/PDFs into one PDF.
    public func combinePDFOutput(directory: String, stem: String = "Combined") -> String {
        uniquePath(directory: directory, stem: stem, ext: "pdf")
    }

    /// Unique output path for a foreground-masked transparent PNG (`<stem> no-bg.png`).
    public func removeBackgroundOutput(_ source: String) -> String {
        let stem = ((source as NSString).lastPathComponent as NSString).deletingPathExtension
        let dir = (source as NSString).deletingLastPathComponent
        return uniquePath(directory: dir, stem: "\(stem) no-bg", ext: "png")
    }

    public static func isImageExtension(_ ext: String) -> Bool {
        let lower = ext.lowercased()
        return ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "webp", "bmp", "gif"].contains(lower)
    }

    public static func isVideoExtension(_ ext: String) -> Bool {
        let lower = ext.lowercased()
        return ["mp4", "mov", "m4v", "avi", "mkv"].contains(lower)
    }

    public static func isPDFExtension(_ ext: String) -> Bool {
        ext.lowercased() == "pdf"
    }

    public static func formatOCRStatus(lineCount: Int) -> String {
        guard lineCount > 0 else { return "No text found" }
        return lineCount == 1 ? "Copied 1 line of text" : "Copied \(lineCount) lines of text"
    }

    /// "Name.ext", then "Name 2.ext", "Name 3.ext", …
    func uniquePath(directory: String, stem: String, ext: String) -> String {
        var n = 1
        while true {
            let name = (n == 1 ? stem : "\(stem) \(n)") + "." + ext
            let path = (directory as NSString).appendingPathComponent(name)
            if !fileExists(path) { return path }
            n += 1
        }
    }
}
