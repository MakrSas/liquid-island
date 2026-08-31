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
    /// Карточку смахнули вправо — она спрятана до обратного свайпа.
    @Published private(set) var isDismissed = false
    /// Сдвиг карточки во время свайпа, в точках.
    @Published private(set) var swipeOffset: CGFloat = 0
    /// Отклик на нажатие: остров чуть подрастает и возвращается.
    @Published private(set) var pressScale: CGFloat = 1

    let media: MediaHub
    let hud: SystemHUD
    private let themeStore: ThemeStore
    private var bag = Set<AnyCancellable>()
    private var hoverOpenWork: DispatchWorkItem?
    private var hoverCloseWork: DispatchWorkItem?
    private var pressWork: DispatchWorkItem?

    var theme: IslandTheme { themeStore.theme }

    init(
        metrics: NotchMetrics,
        media: MediaHub,
        hud: SystemHUD,
        themeStore: ThemeStore = .shared
    ) {
        self.metrics = metrics
        self.media = media
        self.hud = hud
        self.themeStore = themeStore

        // Плашка системного события меняет размер острова так же, как трек.
        hud.$event
            .map { $0 != nil }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                withAnimation(self.theme.motion.open) { self.objectWillChange.send() }
            }
            .store(in: &bag)

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

        themeStore.themeChanged
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

    /// Показывать ли сейчас плашку системного события.
    var hudEvent: SystemEvent? {
        // В раскрытом виде плашка не нужна: пользователь уже смотрит в остров.
        guard phase != .expanded else { return nil }
        guard let event = hud.event else { return nil }
        switch event {
        case .volume: return theme.behavior.showVolumeHUD ? event : nil
        case .brightness: return theme.behavior.showBrightnessHUD ? event : nil
        case .power: return theme.behavior.showPowerHUD ? event : nil
        case .lowBattery: return theme.behavior.showLowBatteryWarning ? event : nil
        }
    }

    /// Размер в покое: плашка события, карточка трека или узкая пилюля.
    var restingSize: CGSize {
        // Предупреждение о заряде — с кнопкой и двумя строками, ему нужна
        // высота больше, чем узкой плашке.
        if let event = hudEvent {
            return event.isWarning ? theme.geometry.warningSize : theme.geometry.hudSize
        }
        guard showsMediaCard else {
            return metrics.hasHardwareNotch ? metrics.closedSize : theme.geometry.closedSize
        }
        return theme.geometry.compactSize
    }

    /// Показываем ли карточку трека вместо пустой пилюли.
    var showsMediaCard: Bool {
        theme.behavior.hoverShowsMedia && hasMedia && !isDismissed
    }

    /// Прозрачность карточки во время свайпа: чем дальше увели, тем бледнее.
    var swipeFade: Double {
        1 - min(abs(Double(swipeOffset)) / Double(Self.swipeThreshold * 1.6), 0.9)
    }

    // MARK: - Свайп по тачпаду

    private static let swipeThreshold: CGFloat = 55

    /// Пришёл горизонтальный сдвиг с тачпада.
    func swipe(by delta: CGFloat) {
        guard phase != .expanded, hasMedia else { return }
        // Вправо смахиваем показанную карточку, влево — возвращаем спрятанную.
        let allowed = isDismissed ? min(delta, 0) : max(delta, 0)
        swipeOffset += allowed
        // Дальше порога тянуть некуда: пусть сопротивляется.
        let limit = Self.swipeThreshold * 1.5
        swipeOffset = min(max(swipeOffset, -limit), limit)
    }

    /// Палец с тачпада убрали — решаем, сработал жест или нет.
    func endSwipe() {
        guard swipeOffset != 0 else { return }
        let passed = abs(swipeOffset) >= Self.swipeThreshold
        withAnimation(theme.motion.open) {
            if passed { isDismissed.toggle() }
            swipeOffset = 0
        }
    }

    var bottomRadius: CGFloat {
        switch phase {
        case .closed, .hovered:
            return hudEvent != nil || showsMediaCard
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

    /// Есть ли что показывать в раскрытом виде.
    var hasContent: Bool { hasMedia || hudEvent != nil }

    /// Нажатие по острову.
    ///
    /// Разворачивать пустой остров незачем — там нечего показать. Вместо
    /// этого он отвечает размером, как Dynamic Island на iPhone: чуть
    /// подрастает под пальцем и возвращается.
    func tap() {
        guard hasContent || phase == .expanded else {
            respondToTouch()
            return
        }
        toggle()
    }

    func toggle() {
        cancelHoverWork()
        transition(to: phase == .expanded ? .hovered : .expanded)
    }

    private func respondToTouch() {
        pressWork?.cancel()
        withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) {
            pressScale = 1.05
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                self.pressScale = 1
            }
        }
        pressWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13, execute: work)
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
