import Foundation

/// Fixed AppleScript for Spotify and the parser of its one-line output.
public enum SpotifyAppleScriptParser {
    /// Field separator: U+241E (SYMBOL FOR RECORD SEPARATOR), which no track metadata uses.
    public static let delimiter = "\u{241E}"

    /// Prints `state ␞ name ␞ artist ␞ album ␞ duration ␞ position ␞ artwork url` or nothing
    /// when Spotify is not running.
    public static let script = """
    if application "Spotify" is not running then return ""
    set sep to character id 9246
    tell application "Spotify"
        set st to player state as string
        if st is "stopped" then return "stopped"
        set t to current track
        return st & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & (duration of t) & sep & (player position) & sep & (artwork url of t)
    end tell
    """

    /// Spotify reports duration in ms (older versions: seconds). Above this it is ms.
    static let msThreshold = 36000.0

    /// nil when nothing is playing or paused (not running, stopped, malformed).
    public static func parse(_ output: String, now: Date = Date()) -> NowPlaying? {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = text.components(separatedBy: delimiter)
        guard fields.count >= 6 else { return nil }
        let state = fields[0].lowercased()
        guard state == "playing" || state == "paused" else { return nil }
        let title = fields[1]
        guard !title.isEmpty else { return nil }

        var duration = number(fields[4])
        if let d = duration, d > msThreshold { duration = d / 1000 }
        let artworkURL = fields.count > 6 ? fields[6].trimmingCharacters(in: .whitespaces) : ""

        return NowPlaying(
            title: title,
            artist: nonEmpty(fields[2]),
            album: nonEmpty(fields[3]),
            duration: duration,
            elapsed: number(fields[5]),
            timestamp: now,
            isPlaying: state == "playing",
            playbackRate: 1,
            bundleIdentifier: "com.spotify.client",
            appName: "Spotify",
            artworkURL: artworkURL.isEmpty || artworkURL == "missing value" ? nil : artworkURL,
            source: .spotifyAppleScript)
    }

    private static func nonEmpty(_ s: String) -> String? { s.isEmpty || s == "missing value" ? nil : s }

    /// AppleScript formats numbers by locale: accept a decimal comma.
    private static func number(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}
