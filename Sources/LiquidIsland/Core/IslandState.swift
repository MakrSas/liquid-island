import SwiftUI
import Combine

/// Состояние острова. Ровно те же четыре фазы, что у Dynamic Island на iPhone:
/// покой → подсветка под курсором → всплывающая активность → раскрытая панель.
enum IslandPhase: Equatable {
    case closed
    case hovered
    case activity
    case expanded
}

@MainActor
final class IslandState: ObservableObject {
    @Published var phase: IslandPhase = .closed
    @Published var metrics: NotchMetrics
    /// Трек, который сейчас показывает всплывающая активность.
    @Published var activityPayload: NowPlaying?

    let media: MediaHub
    private let themeStore: ThemeStore
    private var bag = Set<AnyCancellable>()
    private var hoverOpenWork: DispatchWorkItem?
    private var hoverCloseWork: DispatchWorkItem?
    private var activityWork: DispatchWorkItem?

    var theme: IslandTheme { themeStore.theme }

    init(metrics: NotchMetrics, media: MediaHub, themeStore: ThemeStore = .shared) {
        self.metrics = metrics
        self.media = media
        self.themeStore = themeStore

        media.trackChanged
            .sink { [weak self] track in self?.presentActivity(track) }
            .store(in: &bag)

        // Появление или пропажа трека меняет размер фазы наведения.
        media.$nowPlaying
            .map(\.isEmpty)
            .removeDuplicates()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)

        themeStore.$theme
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
    }

    // MARK: - Размеры

    /// Размер острова в текущей фазе.
    var size: CGSize {
        let g = theme.geometry
        switch phase {
        case .closed:
            return metrics.hasHardwareNotch ? metrics.closedSize : g.closedSize
        case .hovered:
            if theme.behavior.hoverShowsMedia && hasMedia { return g.compactSize }
            let base = metrics.hasHardwareNotch ? metrics.closedSize : g.closedSize
            return CGSize(
                width: base.width + g.hoverPadding.width,
                height: base.height + g.hoverPadding.height
            )
        case .activity:
            return g.compactSize
        case .expanded:
            return g.expandedSize
        }
    }

    var bottomRadius: CGFloat {
        switch phase {
        case .closed:
            return theme.geometry.bottomRadiusClosed
        case .hovered:
            return (theme.behavior.hoverShowsMedia && hasMedia)
                ? theme.geometry.bottomRadiusOpen
                : theme.geometry.bottomRadiusClosed
        case .activity, .expanded: return theme.geometry.bottomRadiusOpen
        }
    }

    var shapeStyle: IslandShape.Style {
        (metrics.hasHardwareNotch || theme.behavior.alwaysUseNotchShape) ? .notch : .floating
    }

    /// Есть ли что показывать в компактном виде.
    var hasMedia: Bool { !media.nowPlaying.isEmpty }

    var isOpen: Bool { phase == .expanded }

    // MARK: - Переходы

    func mouseEntered() {
        cancelHoverWork()
        guard phase != .expanded else { return }
        // Наведение показывает трек. Полный плеер — по клику: раскрывать
        // всё под курсором слишком навязчиво.
        transition(to: .hovered)
        guard theme.behavior.expandOnHover else { return }
        let work = DispatchWorkItem { [weak self] in self?.transition(to: .expanded) }
        hoverOpenWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + theme.behavior.hoverOpenDelay,
            execute: work
        )
    }

    func mouseExited() {
        cancelHoverWork()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.transition(to: self.activityPayload == nil ? .closed : .activity)
        }
        hoverCloseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + theme.behavior.hoverCloseDelay, execute: work)
    }

    func toggle() {
        cancelHoverWork()
        transition(to: phase == .expanded ? .closed : .expanded)
    }

    private func cancelHoverWork() {
        hoverOpenWork?.cancel(); hoverOpenWork = nil
        hoverCloseWork?.cancel(); hoverCloseWork = nil
    }

    private func transition(to next: IslandPhase) {
        guard phase != next else { return }
        let animation = next == .closed ? theme.motion.close : theme.motion.open
        withAnimation(animation) { phase = next }
    }

    // MARK: - Всплывающая активность

    private func presentActivity(_ track: NowPlaying) {
        guard theme.behavior.showLiveActivities else { return }
        activityWork?.cancel()
        withAnimation(theme.motion.open) {
            activityPayload = track
            if phase == .closed { phase = .activity }
        }
        let work = DispatchWorkItem { [weak self] in self?.dismissActivity() }
        activityWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + theme.behavior.liveActivityDuration,
            execute: work
        )
    }

    private func dismissActivity() {
        withAnimation(theme.motion.close) {
            activityPayload = nil
            if phase == .activity { phase = .closed }
        }
    }
}
