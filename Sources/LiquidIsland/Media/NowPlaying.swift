import AppKit

struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var album: String
    var artwork: NSImage?
    var duration: TimeInterval
    var elapsed: TimeInterval
    var isPlaying: Bool
    /// Bundle id приложения-источника, если известен.
    var sourceBundleID: String?

    static let empty = NowPlaying(
        title: "", artist: "", album: "", artwork: nil,
        duration: 0, elapsed: 0, isPlaying: false, sourceBundleID: nil
    )

    var isEmpty: Bool { title.isEmpty && artist.isEmpty }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    static func == (lhs: NowPlaying, rhs: NowPlaying) -> Bool {
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.album == rhs.album &&
        lhs.isPlaying == rhs.isPlaying &&
        abs(lhs.duration - rhs.duration) < 0.5 &&
        abs(lhs.elapsed - rhs.elapsed) < 0.5 &&
        lhs.sourceBundleID == rhs.sourceBundleID &&
        lhs.artwork === rhs.artwork
    }
}

enum MediaCommand {
    case playPause, next, previous
}

/// Источник данных о проигрывании.
protocol MediaProvider: AnyObject {
    var displayName: String { get }
    /// Доступен ли источник в текущей системе (энтайтлменты, установленные приложения…).
    func isAvailable() -> Bool
    func fetch() -> NowPlaying?
    func send(_ command: MediaCommand)
}
