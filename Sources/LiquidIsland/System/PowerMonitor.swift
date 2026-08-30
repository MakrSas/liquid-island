import AppKit
import IOKit.ps

/// Следит за питанием: подключением зарядки и уровнем заряда.
///
/// Здесь всё публично — IOKit сам будит нас, когда состояние меняется.
final class PowerMonitor: @unchecked Sendable {
    private var source: CFRunLoopSource?
    private var lastPlugged: Bool?
    private let onChange: @Sendable (Bool, Int) -> Void

    init(onChange: @escaping @Sendable (Bool, Int) -> Void) {
        self.onChange = onChange
    }

    deinit { stop() }

    func start() {
        lastPlugged = Self.state()?.plugged

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.handleChange()
        }, context)?.takeRetainedValue() else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        self.source = source
    }

    func stop() {
        guard let source else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        self.source = nil
    }

    private func handleChange() {
        guard let state = Self.state() else { return }
        // Уровень заряда меняется постоянно; показывать плашку стоит только на
        // подключении и отключении.
        guard state.plugged != lastPlugged else { return }
        lastPlugged = state.plugged
        onChange(state.plugged, state.charge)
    }

    static func state() -> (plugged: Bool, charge: Int)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for item in list {
            guard let description = IOPSGetPowerSourceDescription(blob, item)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let state = description[kIOPSPowerSourceStateKey] as? String
            let plugged = state == kIOPSACPowerValue
            return (plugged, max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : 0)
        }
        return nil
    }
}
