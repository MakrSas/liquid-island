import AppKit

/// Запасной источник: AppleScript-мост к Spotify и Apple Music.
///
/// Работает без приватных API, но требует разрешения «Автоматизация»
/// и знает только про те приложения, которые мы явно перечислили.
final class ScriptingProvider: MediaProvider {
    struct Target {
        let bundleID: String
        let name: String
        /// Spotify отдаёт длительность в миллисекундах, Music — в секундах.
        let durationDivisor: Double
    }

    static let spotify = Target(bundleID: "com.spotify.client", name: "Spotify", durationDivisor: 1000)
    static let music = Target(bundleID: "com.apple.Music", name: "Music", durationDivisor: 1)

    private let targets = [ScriptingProvider.spotify, ScriptingProvider.music]

    let displayName = "AppleScript"

    private func isRunning(_ target: Target) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).isEmpty
    }

    private var activeTarget: Target? {
        // Предпочитаем то приложение, которое реально играет.
        let running = targets.filter(isRunning)
        for target in running where state(of: target) == "playing" { return target }
        return running.first
    }

    func isAvailable() -> Bool { activeTarget != nil }

    private func run(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        return error == nil ? result : nil
    }

    private func state(of target: Target) -> String {
        run("tell application \"\(target.name)\" to return player state as text")?
            .stringValue?
            .lowercased() ?? ""
    }

    func fetch() -> NowPlaying? {
        guard let target = activeTarget else { return nil }

        // Одним запросом забираем всё, разделяя поля символом, который
        // не встречается в метаданных треков.
        let sep = "\u{1F}"
        let source = """
        tell application "\(target.name)"
            if player state is stopped then return ""
            set t to name of current track
            set a to artist of current track
            set al to album of current track
            set d to duration of current track
            set p to player position
            set s to player state as text
            return t & "\(sep)" & a & "\(sep)" & al & "\(sep)" & (d as text) & "\(sep)" & (p as text) & "\(sep)" & s
        end tell
        """
        guard let raw = run(source)?.stringValue, !raw.isEmpty else { return nil }
        let parts = raw.components(separatedBy: sep)
        guard parts.count >= 6 else { return nil }

        let duration = (Double(parts[3]) ?? 0) / target.durationDivisor
        return NowPlaying(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            artwork: artwork(for: target),
            duration: duration,
            elapsed: Double(parts[4]) ?? 0,
            isPlaying: parts[5].lowercased() == "playing",
            sourceBundleID: target.bundleID
        )
    }

    private func artwork(for target: Target) -> NSImage? {
        // У Music обложка доступна как raw data, у Spotify — по URL.
        if target.bundleID == ScriptingProvider.music.bundleID {
            let source = """
            tell application "Music"
                if (count of artworks of current track) is 0 then return ""
                return raw data of artwork 1 of current track
            end tell
            """
            if let data = run(source)?.data, !data.isEmpty { return NSImage(data: data) }
            return nil
        }

        let source = "tell application \"Spotify\" to return artwork url of current track"
        guard let urlString = run(source)?.stringValue,
              let url = URL(string: urlString),
              let data = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: data)
    }

    func send(_ command: MediaCommand) {
        guard let target = activeTarget else { return }
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        }
        _ = run("tell application \"\(target.name)\" to \(verb)")
    }
}
