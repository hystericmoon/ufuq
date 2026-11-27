import Foundation

/// Finds a GitHub token: `gh auth token`, else a pasted token in a file. Never the Keychain.
public struct GitHubTokenSource: Sendable {
    public enum Origin: Equatable, Sendable { case gh, file }

    /// A GUI app gets no shell `PATH`, so these are tried in order.
    public static let ghPaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]

    public static func defaultTokenPath(home: String) -> String {
        (home.hasSuffix("/") ? String(home.dropLast()) : home) + "/Library/Application Support/Ufuq/github-token"
    }

    private let runCommand: @Sendable (String, [String]) -> (status: Int32, stdout: String)?
    private let readFile: @Sendable (String) -> String?
    private let fileExists: @Sendable (String) -> Bool
    private let tokenPath: String

    /// `runCommand` runs an executable with arguments (the app adds a 5 s timeout) and returns
    /// nil if it cannot be launched.
    public init(runCommand: @escaping @Sendable (String, [String]) -> (status: Int32, stdout: String)?,
                readFile: @escaping @Sendable (String) -> String?,
                fileExists: @escaping @Sendable (String) -> Bool,
                tokenPath: String) {
        self.runCommand = runCommand
        self.readFile = readFile
        self.fileExists = fileExists
        self.tokenPath = tokenPath
    }

    public func token() -> (value: String, origin: Origin)? {
        for path in Self.ghPaths where fileExists(path) {
            if let result = runCommand(path, ["auth", "token"]), result.status == 0 {
                let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return (value, .gh) }
            }
        }
        if let contents = readFile(tokenPath) {
            let value = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return (value, .file) }
        }
        return nil
    }
}
