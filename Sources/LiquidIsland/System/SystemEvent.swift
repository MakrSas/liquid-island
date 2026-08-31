import AppKit

/// Событие системы, которое остров показывает всплывающей плашкой.
enum SystemEvent: Equatable {
    case volume(level: Float, muted: Bool)
    case brightness(level: Float)
    /// Зарядку подключили или отключили.
    case power(plugged: Bool, charge: Int)
    /// Заряд подходит к концу. Отдельно от `power`: тут не короткая плашка,
    /// а предупреждение с кнопкой, и висит оно дольше.
    case lowBattery(charge: Int)

    var icon: String {
        switch self {
        case .volume(let level, let muted):
            if muted || level <= 0 { return "speaker.slash.fill" }
            if level < 0.34 { return "speaker.wave.1.fill" }
            if level < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness(let level):
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .power(let plugged, _):
            return plugged ? "bolt.fill" : "battery.50"
        case .lowBattery:
            return "battery.25"
        }
    }

    var title: String {
        switch self {
        case .volume: return "Громкость"
        case .brightness: return "Яркость"
        case .power(let plugged, _): return plugged ? "Зарядка подключена" : "Зарядка отключена"
        case .lowBattery(let charge): return "\(charge)% заряда"
        }
    }

    /// Значение для шкалы, 0…1. У события зарядки шкала показывает заряд.
    var level: Float {
        switch self {
        case .volume(let level, let muted): return muted ? 0 : level
        case .brightness(let level): return level
        case .power(_, let charge): return Float(charge) / 100
        case .lowBattery(let charge): return Float(charge) / 100
        }
    }

    /// Подпись справа.
    var readout: String {
        switch self {
        case .power(_, let charge): return "\(charge)%"
        case .lowBattery(let charge): return "\(charge)%"
        default: return "\(Int((level * 100).rounded()))"
        }
    }

    /// Предупреждение о заряде показывается развёрнутой плашкой с кнопкой,
    /// остальные — узкой полосой.
    var isWarning: Bool {
        if case .lowBattery = self { return true }
        return false
    }

    /// События одного рода заменяют друг друга, не выстраиваясь в очередь.
    var kind: Int {
        switch self {
        case .volume: return 0
        case .brightness: return 1
        case .power: return 2
        case .lowBattery: return 3
        }
    }
}
