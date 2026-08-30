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
    /// Последний размер острова, присланный из SwiftUI.
    private var lastIslandSize: CGSize = .zero
    /// Кому вернуть фокус, когда остров свернётся.
    private var previousApp: NSRunningApplication?
    private var releaseKeyWork: DispatchWorkItem?
    private var bag = Set<AnyCancellable>()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var scrollMonitor: Any?
    private var localScrollMonitor: Any?
    private var mouseInside = false

    init(
        screen: NSScreen,
        media: MediaHub,
        hud: SystemHUD,
        themeStore: ThemeStore = .shared
    ) {
        self.screen = screen
        let metrics = NotchMetrics.measure(for: screen)
        self.state = IslandState(
            metrics: metrics,
            media: media,
            hud: hud,
            themeStore: themeStore
        )

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
            audio: media.levels,
            hud: hud
        )
        let box = FrameBox()
        root.onSizeChange = { [box] size in
            MainActor.assumeIsolated { box.handler?(size) }
        }
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
        frameBox?.handler = { @Sendable [weak self] size in
            MainActor.assumeIsolated {
            guard let self else { return }
            self.lastIslandSize = size
            if ProcessInfo.processInfo.environment["LIQUID_ISLAND_DEBUG"] == "1" {
                print("размер острова: \(size) стекло=\(self.glassView != nil)")
            }
            self.positionGlass(islandSize: size)
            }
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
            releaseKeyWork?.cancel()
            releaseKeyWork = nil
            restorePreviousApp()
            return
        }
        if theme.palette.activateForGlass {
            // Ключевой статус — обязательное условие для живого стекла.
            // Запоминаем, кому вернуть фокус: прятать себя нельзя, hide
            // убирает все окна приложения, вместе с самим островом.
            if !NSApp.isActive {
                previousApp = NSWorkspace.shared.frontmostApplication
                NSApp.activate(ignoringOtherApps: true)
            }
            panel.makeKeyAndOrderFront(nil)

            // Стекло уже отрисовано — пробуем вернуть фокус прежнему хозяину
            // и посмотреть, переживёт ли стекло потерю ключа.
            if theme.palette.releaseKeyAfterGlass {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.state.phase == .expanded else { return }
                    self.restorePreviousApp()
                }
                releaseKeyWork?.cancel()
                releaseKeyWork = work
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + theme.palette.releaseKeyDelay,
                    execute: work
                )
            }
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
        positionGlass(islandSize: lastIslandSize)
    }

    /// Возвращает фокус тому приложению, которое было впереди до раскрытия.
    private func restorePreviousApp() {
        guard let previousApp, NSApp.isActive else {
            self.previousApp = nil
            return
        }
        self.previousApp = nil
        previousApp.activate()
    }

    /// Кадр стекла в координатах контейнера. AppKit считает снизу вверх,
    /// остров прижат к верхней кромке и отцентрован.
    private func glassFrame(for size: CGSize) -> CGRect {
        let bounds = host.bounds
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.maxY - size.height - state.theme.geometry.floatingTopInset,
            width: size.width,
            height: size.height
        )
    }

    /// Ставит стекло точно под остров. Размер приходит из SwiftUI на каждом
    /// шаге пружины, поэтому собственная анимация здесь не нужна — и вредна:
    /// она бы догоняла уже посчитанное положение.
    private func positionGlass(islandSize size: CGSize) {
        guard let glassView, size.width > 0, size.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glassView.frame = glassFrame(for: size)
        CATransaction.commit()
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
        let outsideClick: (NSEvent) -> Void = { [weak self] _ in
            guard let self, self.state.theme.behavior.dismissOnOutsideClick else { return }
            guard self.state.phase == .expanded else { return }
            guard !self.islandScreenRect.contains(NSEvent.mouseLocation) else { return }
            self.state.dismiss()
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: outsideClick
        )
        // Локальный наблюдатель нужен потому, что остров сам делает
        // приложение активным: клики по нашим же окнам до глобального
        // наблюдателя не доходят.
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { event in
            outsideClick(event)
            return event
        }
        // Переход в другое приложение — тот же сигнал: остров больше не нужен.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // Идентификатор достаём здесь, до перехода на главный актор:
            // само уведомление между потоками передавать нельзя.
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, self.state.theme.behavior.dismissOnOutsideClick else { return }
                guard self.state.phase == .expanded else { return }
                guard pid != ProcessInfo.processInfo.processIdentifier else { return }
                self.state.dismiss()
            }
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

    /// Меню по правому клику. В меню-баре иконки нет, это единственный вход
    /// в настройки и выход из приложения.
    var menu: NSMenu? {
        get { host.menu }
        set { host.menu = newValue }
    }

    func refreshScreenMetrics() {
        applyTheme(state.theme)
    }

    func close() {
        glassView?.removeFromSuperview()
        glassView = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        let monitors = [
            globalMonitor, localMonitor, clickMonitor,
            localClickMonitor, scrollMonitor, localScrollMonitor
        ]
        for monitor in monitors.compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        globalMonitor = nil
        localMonitor = nil
        clickMonitor = nil
        localClickMonitor = nil
        scrollMonitor = nil
        localScrollMonitor = nil
        panel.orderOut(nil)
    }
}
