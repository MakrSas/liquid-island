import AppKit
import CoreAudio

/// Последний рубеж: если ни один скриптуемый плеер не отзывается, спрашиваем
/// у CoreAudio, какое приложение прямо сейчас выводит звук.
///
/// Метаданных трека здесь взять неоткуда — система их не отдаёт без
/// энтайтлмента MediaRemote. Зато мы честно показываем источник: так остров
/// оживает на Telegram, браузере, плеерах без AppleScript.
final class SystemAudioProvider: MediaProvider {
    let displayName = "CoreAudio"

    /// Служебные процессы, которые держат выход открытым, но музыкой не являются.
    private let ignoredBundleIDs: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.soundanalysisd"
    ]

    func isAvailable() -> Bool { playingApplication() != nil }

    /// Кандидаты — все приложения, держащие выход открытым, вместе с их
    /// объектами процесса: по ним можно отвести звук конкретного приложения,
    /// а не всей системы.
    func candidates() -> [(app: NSRunningApplication, process: AudioObjectID)] {
        var found: [(NSRunningApplication, AudioObjectID)] = []
        for object in processObjects() {
            guard isRunningOutput(object), let pid = pid(of: object) else { continue }
            guard let app = NSRunningApplication(processIdentifier: pid) else { continue }
            guard let bundle = app.bundleIdentifier, !ignoredBundleIDs.contains(bundle) else { continue }
            guard bundle != Bundle.main.bundleIdentifier else { continue }
            found.append((app, object))
        }
        return found
    }

    func fetch() -> NowPlaying? {
        guard let app = playingApplication() else { return nil }
        return NowPlaying(
            title: app.localizedName ?? "Звук",
            artist: "",
            album: "",
            artwork: app.icon,
            duration: 0,
            elapsed: 0,
            isPlaying: true,
            sourceBundleID: app.bundleIdentifier,
            supportsTransport: false
        )
    }

    /// Управлять чужим приложением отсюда нечем: медиаклавиши требуют
    /// разрешения «Универсальный доступ», а без него команда просто исчезнет.
    func send(_ command: MediaCommand) {}

    // MARK: - CoreAudio

    private func playingApplication() -> NSRunningApplication? {
        candidates().first?.app
    }

    /// Объект процесса для конкретного приложения.
    func process(for bundleID: String) -> AudioObjectID? {
        candidates().first { $0.app.bundleIdentifier == bundleID }?.process
    }

    private func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private func pid(of object: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func isRunningOutput(_ object: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }
}
