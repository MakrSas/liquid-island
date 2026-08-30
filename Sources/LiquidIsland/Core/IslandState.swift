import SwiftUI
import Combine

/// Состояние острова. Ровно те же четыре фазы, что у Dynamic Island на iPhone:
/// покой → подсветка под курсором → всплывающая активность → раскрытая панель.
enum IslandPhase: Equatable {
    case closed
    case hovered
    case expanded
}

@MainActor
final class IslandState: ObservableObject {
    @Published var phase: IslandPhase = .closed
    @Published var metrics: NotchMetrics

    let media: MediaHub
    private let themeStore: ThemeStore
    private var bag = Set<AnyCancellable>()
    private var hoverOpenWork: DispatchWorkItem?
    private var hoverCloseWork: DispatchWorkItem?

    var theme: IslandTheme { themeStore.theme }

    init(metrics: NotchMetrics, media: MediaHub, themeStore: ThemeStore = .shared) {
        self.metrics = metrics
        self.media = media
        self.themeStore = themeStore

        // Появление или пропажа трека меняет размер острова в покое.
        media.$nowPlaying
            .map(\.isEmpty)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                withAnimation(self.theme.motion.open) { self.objectWillChange.send() }
            }
            .store(in: &bag)

        themeStore.$theme
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
    }

    // MARK: - Размеры

    /// Размер острова в текущей фазе.
    ///
    /// Карточка с треком показывается постоянно и одного размера — наведение
    /// только слегка её увеличивает, а не подменяет другим макетом.
    var size: CGSize {
        let g = theme.geometry
        switch phase {
        case .closed:
            return restingSize
        case .hovered:
            return CGSize(
                width: restingSize.width + g.hoverPadding.width,
                height: restingSize.height + g.hoverPadding.height
            )
        case .expanded:
            return g.expandedSize
        }
    }

    /// Размер в покое: карточка трека, если играет музыка, иначе узкая пилюля.
    private var restingSize: CGSize {
        guard showsMediaCard else {
            return metrics.hasHardwareNotch ? metrics.closedSize : theme.geometry.closedSize
        }
        return theme.geometry.compactSize
    }

    /// Показываем ли карточку трека вместо пустой пилюли.
    var showsMediaCard: Bool { theme.behavior.hoverShowsMedia && hasMedia }

    var bottomRadius: CGFloat {
        switch phase {
        case .closed, .hovered:
            return showsMediaCard
                ? theme.geometry.bottomRadiusOpen
                : theme.geometry.bottomRadiusClosed
        case .expanded:
            return theme.geometry.bottomRadiusOpen
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
        // Раскрытый остров уводом курсора не закрывается — только кликом мимо.
        guard phase != .expanded else { return }
        let work = DispatchWorkItem { [weak self] in self?.transition(to: .closed) }
        hoverCloseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + theme.behavior.hoverCloseDelay, execute: work)
    }

    func toggle() {
        cancelHoverWork()
        transition(to: phase == .expanded ? .hovered : .expanded)
    }

    /// Клик мимо острова — единственный способ его свернуть.
    func dismiss() {
        cancelHoverWork()
        transition(to: .closed)
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

}
