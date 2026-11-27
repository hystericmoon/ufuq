import AppKit
import SwiftUI
import UfuqCore

/// Words for the Now Playing tile and its spoken labels.
enum NowPlayingFormat {
    /// "Bertaut by Nadin Amizah", or just the title.
    static func description(_ track: NowPlaying) -> String {
        track.artist.map { "\(track.title) by \($0)" } ?? track.title
    }

    static func playPauseLabel(_ track: NowPlaying) -> String {
        "\(track.isPlaying ? "Pause" : "Play"), \(description(track))"
    }

    static func value(_ track: NowPlaying) -> String {
        "\(track.isPlaying ? "Playing" : "Paused"), \(description(track))"
    }

    /// Target of a ±10 s seek from the current position, clamped to the track.
    static func seekTarget(_ track: NowPlaying, by delta: TimeInterval, at now: Date) -> TimeInterval {
        let position = track.position(at: now) ?? 0
        var target = max(0, position + delta)
        if let duration = track.duration { target = min(target, duration) }
        return target
    }
}

/// Decodes artwork once per payload; the tile redraws every second.
private enum ArtworkCache {
    private static var lastData: Data?
    private static var lastImage: NSImage?

    static func image(for data: Data) -> NSImage? {
        if lastData == data { return lastImage }
        let image = NSImage(data: data)
        lastData = data
        lastImage = image
        return image
    }
}

/// Small tile (144 x 112): what is playing and previous / play-pause / next.
struct NowPlayingTile: View {
    let track: NowPlaying
    let now: Date

    private static let seekStep: TimeInterval = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NOW PLAYING")
                .font(Tokens.Typography.tileLabel)
                .tracking(0.4)
                .foregroundStyle(Tokens.textSecondary)
                .frame(minHeight: 16, alignment: .leading)
            HStack(spacing: 8) {
                artwork
                VStack(alignment: .leading, spacing: 0) {
                    Text(track.title)
                        .font(Tokens.Typography.value)
                        .foregroundStyle(Tokens.textPrimary)
                        .lineLimit(1)
                    if let artist = track.artist {
                        Text(artist)
                            .font(Tokens.Typography.caption)
                            .foregroundStyle(Tokens.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                control("backward.fill", label: "Previous track") { NowPlayingControl.send(.previous) }
                Spacer(minLength: 0)
                control(track.isPlaying ? "pause.fill" : "play.fill", label: NowPlayingFormat.playPauseLabel(track)) {
                    NowPlayingControl.send(.playPause)
                }
                Spacer(minLength: 0)
                control("forward.fill", label: "Next track") { NowPlayingControl.send(.next) }
            }
        }
        .onKeyPress(.space) {
            NowPlayingControl.send(.playPause)
            return .handled
        }
        .onKeyPress(.leftArrow) { seek(-Self.seekStep) }
        .onKeyPress(.rightArrow) { seek(Self.seekStep) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now playing")
        .accessibilityValue(NowPlayingFormat.value(track))
        .accessibilityAction(named: Text(NowPlayingFormat.playPauseLabel(track))) { NowPlayingControl.send(.playPause) }
        .accessibilityAction(named: Text("Next track")) { NowPlayingControl.send(.next) }
        .accessibilityAction(named: Text("Previous track")) { NowPlayingControl.send(.previous) }
        .accessibilityAction(named: Text("Forward 10 seconds")) { _ = seek(Self.seekStep) }
        .accessibilityAction(named: Text("Back 10 seconds")) { _ = seek(-Self.seekStep) }
    }

    private func seek(_ delta: TimeInterval) -> KeyPress.Result {
        guard track.position(at: now) != nil else { return .ignored }
        NowPlayingControl.send(.seek(to: NowPlayingFormat.seekTarget(track, by: delta, at: now)))
        return .handled
    }

    @ViewBuilder
    private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        Group {
            if let data = track.artwork, let image = ArtworkCache.image(for: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let urlString = track.artworkURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        glyph
                    }
                }
            } else {
                glyph
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    private var glyph: some View {
        ZStack {
            Tokens.Fill.track
            Image(systemName: "music.note")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tokens.textSecondary)
        }
    }

    private func control(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tokens.textPrimary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
