import AppKit
import SwiftUI
import Combine

/// Держит одно окно-остров на одном экране и следит за его геометрией.
@MainActor
final class IslandController {
    let screen: NSScreen
    let state: IslandState

    private let panel: IslandPanel
    private let host: PassthroughHostingView<AnyView>
    private var bag = Set<AnyCancellable>()

    init(screen: NSScreen, media: MediaHub, themeStore: ThemeStore = .shared) {
        self.screen = screen
        let metrics = NotchMetrics.measure(for: screen)
        self.state = IslandState(metrics: metrics, media: media, themeStore: themeStore)

        let frame = IslandController.panelFrame(for: screen, theme: themeStore.theme)
        panel = IslandPanel(contentRect: frame)

        let root = IslandRootView(state: state, media: media, themeStore: themeStore)
        host = PassthroughHostingView(rootView: AnyView(root))
        host.frame = CGRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()

        // Кликабельна только сама фигура острова, всё остальное — сквозное.
        state.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateInteractiveArea() }
            .store(in: &bag)

        themeStore.$theme
            .receive(on: RunLoop.main)
            .sink { [weak self] theme in self?.applyTheme(theme) }
            .store(in: &bag)

        updateInteractiveArea()
    }

    /// Окно всегда размером с самое большое состояние — так анимация
    /// раскрытия не упирается в границы окна.
    private static func panelFrame(for screen: NSScreen, theme: IslandTheme) -> CGRect {
        let metrics = NotchMetrics.measure(for: screen)
        let width = max(theme.geometry.expandedSize.width, metrics.closedSize.width) + 80
        let height = theme.geometry.expandedSize.height
            + theme.geometry.floatingTopInset
            + 60
        return CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    private func applyTheme(_ theme: IslandTheme) {
        state.metrics = NotchMetrics.measure(for: screen)
        let frame = IslandController.panelFrame(for: screen, theme: theme)
        panel.setFrame(frame, display: true)
        updateInteractiveArea()
    }

    /// Прямоугольник в координатах хост-вью (у AppKit начало координат снизу).
    private func updateInteractiveArea() {
        let size = state.size
        let inset = state.metrics.hasHardwareNotch ? 0 : state.theme.geometry.floatingTopInset
        let bounds = host.bounds
        // Небольшой запас по краям, чтобы курсор не «терял» остров на анимации.
        let padding: CGFloat = 6
        host.interactiveRect = CGRect(
            x: bounds.midX - size.width / 2 - padding,
            y: bounds.maxY - size.height - inset - padding,
            width: size.width + padding * 2,
            height: size.height + inset + padding * 2
        )
    }

    func refreshScreenMetrics() {
        applyTheme(state.theme)
    }

    func close() {
        panel.orderOut(nil)
    }
}
