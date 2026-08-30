import AppKit

/// Следит за яркостью встроенного экрана.
///
/// Публичного способа узнать яркость на Apple Silicon нет: `IODisplay`
/// встроенную панель не отдаёт. Берём из приватного DisplayServices —
/// того же, которым пользуется системный HUD. Уведомления оттуда наружу не
/// торчат, поэтому опрашиваем: вызов дешёвый, четыре раза в секунду
/// незаметны.
final class BrightnessMonitor: @unchecked Sendable {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    private var handle: UnsafeMutableRawPointer?
    private var getBrightness: GetBrightness?
    private var timer: DispatchSourceTimer?
    private var lastValue: Float = -1
    private let onChange: @Sendable (Float) -> Void

    init(onChange: @escaping @Sendable (Float) -> Void) {
        self.onChange = onChange
        load()
    }

    deinit {
        timer?.cancel()
        if let handle { dlclose(handle) }
    }

    private func load() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY) else { return }
        self.handle = handle
        if let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
            getBrightness = unsafeBitCast(symbol, to: GetBrightness.self)
        }
    }

    var isAvailable: Bool { getBrightness != nil }

    func start(interval: TimeInterval = 0.25) {
        guard isAvailable else { return }
        lastValue = read() ?? -1

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(80))
        timer.setEventHandler { [weak self] in
            guard let self, let value = self.read() else { return }
            // Мелкое дрожание значения не считаем изменением.
            guard abs(value - self.lastValue) > 0.005 else { return }
            self.lastValue = value
            self.onChange(value)
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func read() -> Float? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        let display = CGMainDisplayID()
        guard getBrightness(display, &value) == 0 else { return nil }
        return value
    }
}
