import AppKit
import Combine

/// Собирает Now Playing из доступных источников и держит его актуальным.
///
/// Провайдеры перебираются по приоритету: системный MediaRemote, если он
/// открыт, иначе AppleScript-мост. Порядок легко расширить своими модулями.
@MainActor
class MediaHub: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying = .empty
    @Published private(set) var activeProviderName: String = "—"
    /// Взводится при смене трека — по нему остров показывает всплывающую активность.
    let trackChanged = PassthroughSubject<NowPlaying, Never>()

    private var providers: [MediaProvider] = []
    private var timer: Timer?
    private var lastTrackKey: String = ""

    init() {
        let candidates: [MediaProvider] = [MediaRemoteProvider(), ScriptingProvider()]
        providers = candidates
        resolveProvider()
    }

    func start(interval: TimeInterval = 1.0) {
        stop()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func resolveProvider() {
        activeProviderName = providers.first(where: { $0.isAvailable() })?.displayName ?? "—"
    }

    private func tick() {
        var fresh: NowPlaying?
        for provider in providers {
            if let value = provider.fetch() {
                fresh = value
                if activeProviderName != provider.displayName {
                    activeProviderName = provider.displayName
                }
                break
            }
        }

        let value = fresh ?? .empty
        let key = "\(value.title)|\(value.artist)"
        if !value.isEmpty, key != lastTrackKey {
            lastTrackKey = key
            trackChanged.send(value)
        }
        if value.isEmpty { lastTrackKey = "" }
        if value != nowPlaying { nowPlaying = value }
    }

    /// Подставить трек вручную — используется рендерером превью.
    func setPreviewTrack(_ track: NowPlaying) {
        nowPlaying = track
        activeProviderName = "Preview"
    }

    func send(_ command: MediaCommand) {
        for provider in providers where provider.isAvailable() {
            provider.send(command)
            break
        }
        // Не ждём следующего тика — отзывчивость важнее точности на полсекунды.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            Task { @MainActor in self?.tick() }
        }
    }
}
