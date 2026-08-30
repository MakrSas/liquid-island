import AppKit
import Combine

/// Собирает системные события и отдаёт их острову.
///
/// Первое значение каждого источника проглатывается: при запуске нам сообщают
/// текущее состояние, а показывать плашку на пустом месте не нужно.
@MainActor
final class SystemHUD: ObservableObject {
    @Published private(set) var event: SystemEvent?

    private var volumeMonitor: VolumeMonitor?
    private var brightnessMonitor: BrightnessMonitor?
    private var powerMonitor: PowerMonitor?
    private var hideWork: DispatchWorkItem?
    private var duration: TimeInterval = 1.6

    func start(duration: TimeInterval) {
        stop()
        self.duration = duration

        let volume = VolumeMonitor { [weak self] level, muted in
            Task { @MainActor in self?.present(.volume(level: level, muted: muted)) }
        }
        volume.start()
        volumeMonitor = volume

        let brightness = BrightnessMonitor { [weak self] level in
            Task { @MainActor in self?.present(.brightness(level: level)) }
        }
        brightness.start()
        brightnessMonitor = brightness

        let power = PowerMonitor { [weak self] plugged, charge in
            Task { @MainActor in self?.present(.power(plugged: plugged, charge: charge)) }
        }
        power.start()
        powerMonitor = power
    }

    func stop() {
        volumeMonitor?.stop(); volumeMonitor = nil
        brightnessMonitor?.stop(); brightnessMonitor = nil
        powerMonitor?.stop(); powerMonitor = nil
        hideWork?.cancel(); hideWork = nil
        event = nil
    }

    private func present(_ fresh: SystemEvent) {
        event = fresh
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.event = nil }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    /// Убрать плашку немедленно — например, когда пользователь раскрыл остров.
    func dismiss() {
        hideWork?.cancel()
        hideWork = nil
        event = nil
    }
}
