import AppKit

/// Одна активность в острове.
///
/// До этого остров показывал ровно одно состояние, а источники спорили за
/// него порядком проверок в коде. Активность делает это явным: у каждой есть
/// приоритет, и решает он, а не порядок ветвлений.
enum IslandActivity: Equatable, Identifiable {
    case media(NowPlaying)
    case system(SystemEvent)

    var id: String {
        switch self {
        case .media: return "media"
        case .system(let event): return "system.\(event.kind)"
        }
    }

    /// Чем больше, тем важнее. Предупреждение перебивает всё, плашка —
    /// музыку, музыка живёт фоном.
    var priority: Int {
        switch self {
        case .system(let event): return event.isWarning ? 300 : 200
        case .media: return 100
        }
    }

    /// Значок для сжатого показа, когда активность не главная.
    var badgeIcon: String {
        switch self {
        case .media(let track): return track.isPlaying ? "waveform" : "pause.fill"
        case .system(let event): return event.icon
        }
    }
}

/// Собирает активности из источников и раскладывает по важности.
///
/// Главную остров показывает целиком, остальные — значками рядом. Так их
/// видно все сразу, а не по очереди, и любую можно вывести вперёд нажатием.
@MainActor
final class ActivityCenter: ObservableObject {
    /// Какую активность пользователь вывел вперёд вручную.
    @Published private(set) var pinned: String?

    private let media: MediaHub
    private let hud: SystemHUD

    init(media: MediaHub, hud: SystemHUD) {
        self.media = media
        self.hud = hud
    }

    /// Все активности, от важной к менее важной.
    var activities: [IslandActivity] {
        var list: [IslandActivity] = []
        if let event = hud.event { list.append(.system(event)) }
        if !media.nowPlaying.isEmpty { list.append(.media(media.nowPlaying)) }

        list.sort { left, right in
            // Закреплённая идёт первой, дальше по приоритету.
            if left.id == pinned { return true }
            if right.id == pinned { return false }
            return left.priority > right.priority
        }
        return list
    }

    var primary: IslandActivity? { activities.first }
    var others: [IslandActivity] { Array(activities.dropFirst()) }

    /// Вывести активность вперёд. Повторное нажатие снимает закрепление.
    func pin(_ activity: IslandActivity) {
        pinned = pinned == activity.id ? nil : activity.id
    }

    /// Закрепление живёт, только пока активность существует.
    func forgetMissingPin() {
        guard let pinned else { return }
        if !activities.contains(where: { $0.id == pinned }) { self.pinned = nil }
    }
}
