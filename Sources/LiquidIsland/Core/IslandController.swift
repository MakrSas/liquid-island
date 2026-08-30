import AppKit
import SwiftUI
import Combine

/// Держит одно окно-остров на одном экране и следит за его геометрией.
@MainActor
final class IslandController {
    let screen: NSScreen
    let state: IslandState

    private let panel: IslandPanel
    private let host: IslandHostingView<AnyView>
    private var bag = Set<AnyCancellable>()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var mouseInside = false

    init(screen: NSScreen, media: MediaHub, themeStore: ThemeStore = .shared) {
        self.screen = screen
        let metrics = NotchMetrics.measure(for: screen)
        self.state = IslandState(metrics: metrics, media: media, themeStore: themeStore)

        let frame = IslandController.panelFrame(for: screen, theme: themeStore.theme)
        panel = IslandPanel(contentRect: frame)

        let root = IslandRootView(state: state, media: media, themeStore: themeStore)
        host = IslandHostingView(rootView: AnyView(root))
        host.frame = CGRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()

        // Кликабельна только сама фигура острова, всё остальное — сквозное.
        state.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncMouseRegion() }
            .store(in: &bag)

        themeStore.$theme
            .receive(on: RunLoop.main)
            .sink { [weak self] theme in self?.applyTheme(theme) }
            .store(in: &bag)

        installMouseMonitors()
        syncMouseRegion()
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
        syncMouseRegion()
    }

    // MARK: - Мышь

    /// Прямоугольник острова в координатах экрана.
    private var islandScreenRect: CGRect {
        let size = state.size
        let inset = state.theme.geometry.floatingTopInset
        // Небольшой запас, чтобы курсор не «терял» остров прямо на анимации.
        let padding: CGFloat = 4
        return CGRect(
            x: screen.frame.midX - size.width / 2 - padding,
            y: screen.frame.maxY - size.height - inset - padding,
            width: size.width + padding * 2,
            height: size.height + inset + padding
        )
    }

    /// Окно занимает широкую полосу вверху экрана, но перехватывать мышь оно
    /// должно только там, где нарисован остров. Иначе оно съедает клики по
    /// меню-бару и по окнам под собой.
    private func installMouseMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] _ in self?.syncMouseRegion() }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged],
            handler: handler
        )
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] event in
            self?.syncMouseRegion()
            return event
        }
    }

    /// Обновляет и проходимость окна, и фазу острова — одним решением,
    /// чтобы они не могли разойтись.
    private func syncMouseRegion() {
        let inside = islandScreenRect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
        guard inside != mouseInside else { return }
        mouseInside = inside
        if inside { state.mouseEntered() } else { state.mouseExited() }
    }

    func refreshScreenMetrics() {
        applyTheme(state.theme)
    }

    func close() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        panel.orderOut(nil)
    }
}
