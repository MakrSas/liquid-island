import AppKit
import Combine
import CoreAudio

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

    /// Реальные уровни звука для эквалайзера.
    let levels = AudioLevels()

    private let providers: [MediaProvider]
    private let queue = DispatchQueue(label: "app.liquidisland.media", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastTrackKey: String = ""
    /// Опрос уже идёт — не ставим второй в очередь, если источник тормозит.
    private var polling = false
    private nonisolated let accentCache = Guarded<(key: String, color: NSColor?)?>(nil)

    private let audioProvider = SystemAudioProvider()

    init() {
        providers = [MediaRemoteProvider(), ScriptingProvider(), audioProvider]
    }

    func start(interval: TimeInterval = 1.0) {
        stop()
        // Таймер тикает на главной очереди: сам он ничего тяжёлого не делает,
        // а трогать изолированный главным актором объект с чужой очереди нельзя.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        levels.stop()
    }

    /// Опрос источников. Сам метод лёгкий: вся работа уходит на фоновую
    /// очередь, потому что AppleScript синхронен и стоит десятки миллисекунд.
    private func poll() {
        guard !polling else { return }
        polling = true
        let providers = self.providers
        queue.async { [weak self] in
            guard let self else { return }
            var result: (NowPlaying, String)?
            for provider in providers {
                if var value = provider.fetch() {
                    value.accent = self.accent(for: value)
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

    private func apply(_ result: (NowPlaying, String)?) {
        var value = result?.0 ?? .empty

        // Источник, найденный по звуку, знает только то, что приложение
        // держит выход открытым. Fastpotify или браузер на паузе выглядят
        // для него точно так же, как играющие. Настоящий ответ даёт сам
        // сигнал: есть звук — играет, нет — стоит.
        if !value.isEmpty, !value.supportsTransport {
            value.isPlaying = levels.isRunning ? levels.hasSignal : true
        }
        let name = result?.1 ?? "—"
        if activeProviderName != name { activeProviderName = name }

        let key = "\(value.title)|\(value.artist)"
        if !value.isEmpty, key != lastTrackKey {
            lastTrackKey = key
            trackChanged.send(value)
        }
        if value.isEmpty { lastTrackKey = "" }
        if value != nowPlaying { nowPlaying = value }

        updateTap(for: value)
    }

    /// Решает, что слушать отводом.
    ///
    /// Для источника, найденного по звуку, отвод наводится на его собственный
    /// процесс. Иначе выходит нелепость: имя берётся у одного приложения, а
    /// сигнал — со всего выхода, и браузер на фоне выдаёт паузу плеера за
    /// воспроизведение.
    private func updateTap(for value: NowPlaying) {
        // Отвод держим, пока источник есть: у найденного по звуку именно он
        // и отвечает на вопрос, играет ли тот. Останавливать его по паузе
        // значило бы отключать то, чем пауза и определяется.
        let needsTap = value.isPlaying || (!value.isEmpty && !value.supportsTransport)
        guard needsTap else {
            if levels.isRunning { levels.stop() }
            return
        }

        // Скриптуемые плееры сами говорят, что играют, — там отвод нужен
        // только для эквалайзера, и слушать можно весь выход.
        var target: [AudioObjectID] = []
        if !value.supportsTransport, let bundleID = value.sourceBundleID,
           let process = audioProvider.process(for: bundleID) {
            target = [process]
        }

        if levels.isRunning {
            levels.retarget(to: target)
        } else {
            levels.start(processes: target)
        }
    }

    /// Разбор обложки стоит недёшево, а меняется она только вместе с треком.
    private nonisolated func accent(for track: NowPlaying) -> NSColor? {
        guard let artwork = track.artwork else { return nil }
        let key = "\(track.title)|\(track.artist)"
        return accentCache.withLock { cache in
            if cache?.key == key { return cache?.color }
            let color = ArtworkColor.accent(from: artwork)
            cache = (key, color)
            return color
        }
    }

    /// Подставить трек вручную — используется рендерером превью.
    func setPreviewTrack(_ track: NowPlaying) {
        nowPlaying = track
        activeProviderName = "Preview"
    }

    /// Переводит в приложение, откуда идёт звук.
    ///
    /// Bundle id известен не всегда: скриптуемые плееры называют себя сами,
    /// источник, найденный по звуку, — тоже. Если его нет, идти некуда.
    func revealSource() {
        guard let bundleID = nowPlaying.sourceBundleID,
              let app = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .first
        else { return }
        app.activate(options: [.activateAllWindows])
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
