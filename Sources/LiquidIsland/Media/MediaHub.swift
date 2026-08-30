import AppKit
import Combine

/// Собирает Now Playing из доступных источников и держит его актуальным.
///
/// Опрос идёт целиком на фоновой очереди: AppleScript синхронен и стоит
/// десятки миллисекунд, а на главном потоке это видно как рывки анимации.
/// В главный поток попадает только готовый результат.
@MainActor
class MediaHub: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying = .empty
    @Published private(set) var activeProviderName: String = "—"
    /// Взводится при смене трека — по нему остров показывает всплывающую активность.
    let trackChanged = PassthroughSubject<NowPlaying, Never>()

    private let providers: [MediaProvider]
    private let queue = DispatchQueue(label: "app.liquidisland.media", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastTrackKey: String = ""
    /// Опрос уже идёт — не ставим второй в очередь, если источник тормозит.
    private var polling = false

    init() {
        providers = [MediaRemoteProvider(), ScriptingProvider()]
    }

    func start(interval: TimeInterval = 1.0) {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Вызывается на фоновой очереди.
    private nonisolated func poll() {
        Task { @MainActor in
            guard !self.polling else { return }
            self.polling = true
            let providers = self.providers
            self.queue.async {
                var result: (NowPlaying, String)?
                for provider in providers {
                    if let value = provider.fetch() {
                        result = (value, provider.displayName)
                        break
                    }
                }
                Task { @MainActor in
                    self.polling = false
                    self.apply(result)
                }
            }
        }
    }

    private func apply(_ result: (NowPlaying, String)?) {
        let value = result?.0 ?? .empty
        let name = result?.1 ?? "—"
        if activeProviderName != name { activeProviderName = name }

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
        let providers = self.providers
        queue.async {
            for provider in providers where provider.fetch() != nil {
                provider.send(command)
                break
            }
        }
        // Не ждём следующего тика — отзывчивость важнее точности на полсекунды.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.poll()
        }
    }
}
