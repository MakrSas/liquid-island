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
    private var glassView: IslandGlassView?
    private weak var glassContainer: NSView?
    private var frameBox: FrameBox?
    /// Последний кадр острова, присланный из SwiftUI.
    private var lastIslandFrame: CGRect = .zero
    private var bag = Set<AnyCancellable>()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var clickMonitor: Any?
    private var scrollMonitor: Any?
    private var localScrollMonitor: Any?
    private var mouseInside = false

    init(screen: NSScreen, media: MediaHub, themeStore: ThemeStore = .shared) {
        self.screen = screen
        let metrics = NotchMetrics.measure(for: screen)
        self.state = IslandState(metrics: metrics, media: media, themeStore: themeStore)

        let frame = IslandController.panelFrame(for: screen, theme: themeStore.theme)
        panel = IslandPanel(contentRect: frame)

        // Стекло — отдельный слой под SwiftUI: его кадром и формой управляем
        // сами, иначе оконный сервер рисует его прямоугольником во всю ширину.
        let container = NSView(frame: CGRect(origin: .zero, size: frame.size))
        container.autoresizingMask = [.width, .height]
        self.glassContainer = container

        var root = IslandRootView(
            state: state,
            media: media,
            themeStore: themeStore,
            audio: media.levels
        )
        let box = FrameBox()
        root.onFrameChange = { [box] frame in box.handler?(frame) }
        host = IslandHostingView(rootView: AnyView(root))
        self.frameBox = box
        host.frame = CGRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        panel.contentView = container

        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()

        // Кликабельна только сама фигура острова, всё остальное — сквозное.
        state.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.syncMouseRegion()
                self.layoutGlass()
                // Остров уменьшился — заставляем окно перерисовать всё,
                // иначе в прозрачной панели остаются несвежие пиксели.
                self.host.needsDisplay = true
                self.panel.viewsNeedDisplay = true
                self.panel.displayIfNeeded()
            }
            .store(in: &bag)

        themeStore.themeChanged
            .receive(on: RunLoop.main)
            .sink { [weak self] theme in self?.applyTheme(theme) }
            .store(in: &bag)

        // Стекло следует за островом кадр в кадр: своя анимация всегда лишь
        // приблизительно похожа на пружину SwiftUI, и рассинхрон видно рывком.
        frameBox?.handler = { [weak self] frame in
            guard let self else { return }
            self.lastIslandFrame = frame
            if ProcessInfo.processInfo.environment["LIQUID_ISLAND_DEBUG"] == "1" {
                print("кадр острова: \(frame)  host=\(self.host.bounds.size)")
            }
            self.positionGlass(islandFrameInHost: frame)
        }
        installMouseMonitors()
        syncMouseRegion()
        layoutGlass()
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
        layoutGlass()
    }

    /// Печатает, что на самом деле лежит в окне: AppKit на macOS 26 умеет
    /// подкладывать окнам собственный фон, и его легко принять за свой.
    func dumpHierarchy() {
        print("panel: frame=\(panel.frame) opaque=\(panel.isOpaque) bg=\(panel.backgroundColor) shadow=\(panel.hasShadow)")
        func walk(_ view: NSView, depth: Int) {
            let pad = String(repeating: "  ", count: depth)
            print("\(pad)\(type(of: view)) frame=\(view.frame) hidden=\(view.isHidden) alpha=\(view.alphaValue)")
            for sub in view.subviews { walk(sub, depth: depth + 1) }
        }
        if let content = panel.contentView { walk(content, depth: 1) }
    }

    /// Создаёт или убирает слой стекла. Положение задаёт `positionGlass`.
    ///
    /// Стекло не прячется, а создаётся и уничтожается: композицию гасит
    /// оконный сервер, и скрытая вьюха оставляет эффект висеть на экране.
    private func layoutGlass() {
        let theme = state.theme
        guard theme.palette.useLiquidGlass, state.phase == .expanded else {
            glassView?.removeFromSuperview()
            glassView = nil
            return
        }
        guard glassView == nil else { return }

        let fresh = IslandGlassView(frame: .zero)
        fresh.configure(
            cornerRadius: theme.geometry.bottomRadiusOpen,
            isClear: theme.palette.glassStyle == .clear,
            tint: theme.palette.glassTint?.nsColor,
            isInteractive: theme.palette.glassInteractive
        )
        glassContainer?.addSubview(fresh, positioned: .below, relativeTo: host)
        glassView = fresh
        // Обновление кадра из SwiftUI могло прийти до создания слоя — тогда
        // он остался бы нулевого размера и стекла просто не было бы видно.
        positionGlass(islandFrameInHost: lastIslandFrame)
    }

    /// Ставит стекло точно под остров. Кадр приходит из SwiftUI на каждом
    /// шаге анимации, поэтому собственная анимация здесь не нужна — и вредна:
    /// она бы догоняла уже посчитанное положение.
    private func positionGlass(islandFrameInHost rect: CGRect) {
        guard let glassView, rect.width > 0, rect.height > 0 else { return }
        // SwiftUI считает сверху вниз, AppKit — снизу вверх.
        let converted = CGRect(
            x: rect.minX,
            y: host.bounds.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glassView.frame = converted
        CATransaction.commit()
        if ProcessInfo.processInfo.environment["LIQUID_ISLAND_DEBUG"] == "1" {
            print("стекло -> \(converted) hidden=\(glassView.isHidden) super=\(glassView.superview != nil)")
        }
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
        // Свайп по тачпаду поверх острова: вправо — убрать карточку,
        // влево — вернуть. Ловим и локально, и глобально: окно почти всё
        // время сквозное, и события до него сами не доходят.
        let scroll: (NSEvent) -> Void = { [weak self] event in
            guard let self, self.mouseInside else { return }
            guard event.hasPreciseScrollingDeltas else { return }
            if event.phase == .ended || event.momentumPhase == .began {
                self.state.endSwipe()
            } else if event.phase == .changed || event.phase == .began {
                self.state.swipe(by: event.scrollingDeltaX)
            }
        }
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel], handler: scroll)
        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            scroll(event)
            return event
        }

        // Раскрытый остров закрывается кликом мимо, а не уводом курсора:
        // иначе им невозможно пользоваться, не удерживая мышь внутри.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self, self.state.phase == .expanded else { return }
            guard !self.islandScreenRect.contains(NSEvent.mouseLocation) else { return }
            self.state.dismiss()
        }
    }

    /// Обновляет и проходимость окна, и фазу острова — одним решением,
    /// чтобы они не могли разойтись.
    private func syncMouseRegion() {
        // Проходимость всегда считается по фигуре острова, даже когда он
        // раскрыт: клик мимо должен и дойти до приложения под нами, и закрыть
        // остров — этим занимается отдельный наблюдатель за нажатиями.
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
        glassView?.removeFromSuperview()
        glassView = nil
        let monitors = [globalMonitor, localMonitor, clickMonitor, scrollMonitor, localScrollMonitor]
        for monitor in monitors.compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        globalMonitor = nil
        localMonitor = nil
        clickMonitor = nil
        scrollMonitor = nil
        localScrollMonitor = nil
        panel.orderOut(nil)
    }
}
