import AppKit

/// Мост к приватному фреймворку MediaRemote.
///
/// Даёт «системный» Now Playing — ровно то, что показывает сам macOS
/// (Spotify, Apple Music, браузеры, что угодно).
/// Начиная с macOS 15.4 Apple закрыла часть этих символов для приложений
/// без специального энтайтлмента, поэтому мост всегда проверяет себя
/// в `isAvailable()` и молча уступает место запасным провайдерам.
final class MediaRemoteProvider: MediaProvider {
    let displayName = "MediaRemote"

    private typealias GetInfo = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias GetIsPlaying = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias SendCommand = @convention(c) (Int, [String: Any]?) -> Bool

    private var handle: UnsafeMutableRawPointer?
    private var getInfo: GetInfo?
    private var getIsPlaying: GetIsPlaying?
    private var sendCommand: SendCommand?

    private final class Box<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }

    init() { load() }

    deinit { if let handle { dlclose(handle) } }

    private func load() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_LAZY) else { return }
        self.handle = handle

        if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            getInfo = unsafeBitCast(sym, to: GetInfo.self)
        }
        if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            getIsPlaying = unsafeBitCast(sym, to: GetIsPlaying.self)
        }
        if let sym = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendCommand = unsafeBitCast(sym, to: SendCommand.self)
        }
    }

    func isAvailable() -> Bool {
        guard getInfo != nil else { return false }
        // Пробный вызов: если система молчит дольше секунды — символы есть,
        // но доступа нет, и полагаться на них нельзя.
        return rawInfo(timeout: 1.0) != nil
    }

    private func rawInfo(timeout: TimeInterval) -> [String: Any]? {
        guard let getInfo else { return nil }
        let box = Box<[String: Any]?>(nil)
        let sem = DispatchSemaphore(value: 0)
        getInfo(DispatchQueue.global(qos: .userInitiated)) { info in
            box.value = info
            sem.signal()
        }
        guard sem.wait(timeout: .now() + timeout) == .success else { return nil }
        return box.value
    }

    private func playingState(timeout: TimeInterval) -> Bool? {
        guard let getIsPlaying else { return nil }
        let box = Box<Bool?>(nil)
        let sem = DispatchSemaphore(value: 0)
        getIsPlaying(DispatchQueue.global(qos: .userInitiated)) { playing in
            box.value = playing
            sem.signal()
        }
        guard sem.wait(timeout: .now() + timeout) == .success else { return nil }
        return box.value
    }

    func fetch() -> NowPlaying? {
        guard let info = rawInfo(timeout: 0.6) else { return nil }

        let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        let album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
        guard !title.isEmpty || !artist.isEmpty else { return nil }

        let duration = info["kMRMediaRemoteNowPlayingInfoDuration"] as? TimeInterval ?? 0
        var elapsed = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? TimeInterval ?? 0
        let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
        let playing = playingState(timeout: 0.4) ?? (rate > 0)

        // Экстраполируем позицию от момента, когда система её зафиксировала.
        if playing, let stamp = info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date {
            elapsed += Date().timeIntervalSince(stamp)
            if duration > 0 { elapsed = min(elapsed, duration) }
        }

        var artwork: NSImage?
        if let data = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
            artwork = NSImage(data: data)
        }

        return NowPlaying(
            title: title, artist: artist, album: album, artwork: artwork,
            duration: duration, elapsed: max(elapsed, 0), isPlaying: playing,
            sourceBundleID: nil
        )
    }

    func send(_ command: MediaCommand) {
        guard let sendCommand else { return }
        let code: Int
        switch command {
        case .playPause: code = 2
        case .next: code = 4
        case .previous: code = 5
        }
        _ = sendCommand(code, nil)
    }
}
