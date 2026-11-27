import Foundation
import UfuqCore

/// Bridge from the tile (a plain value view) to the module: set once at launch.
enum NowPlayingControl {
    /// Sends a command to the source in use, then refreshes. Does nothing until the app wires it.
    static var send: (NowPlayingCommand) -> Void = { _ in }
    /// For Settings.
    static var module: NowPlayingModule?
}
