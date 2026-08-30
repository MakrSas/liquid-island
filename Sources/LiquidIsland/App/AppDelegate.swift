import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let media = MediaHub()
    private let themeStore = ThemeStore.shared
    private let hud = SystemHUD()
    private var controllers: [CGDirectDisplayID: IslandController] = [:]
    private var bag = Set<AnyCancellable>()
    private var statusItem: NSStatusItem?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Приложение без Dock-иконки: остров — это и есть весь интерфейс.
        NSApp.setActivationPolicy(.accessory)

        media.start()
        hud.start(duration: themeStore.theme.behavior.hudDuration)
        rebuildIslands()
        installStatusItem()
        if ProcessInfo.processInfo.environment["LIQUID_ISLAND_DEBUG"] == "1" { dumpDiagnostics() }
        if ProcessInfo.processInfo.environment["LIQUID_ISLAND_TAP_TEST"] == "1" {
            media.levels.start()
            for delay in stride(from: 2.0, through: 8.0, by: 1.0) {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    let text = self.media.levels.bands
                        .map { String(format: "%.2f", $0) }
                        .joined(separator: " ")
                    let stats = self.media.levels.debugStats
                    print("tap \(Int(delay))s: running=\(self.media.levels.isRunning) [\(text)] callbacks=\(stats.callbacks) peak=\(String(format: "%.4f", stats.peak))")
                }
            }
        }

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildIslands() }
            .store(in: &bag)

        themeStore.themeChanged
            .map(\.behavior.displayMode)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.rebuildIslands() }
            .store(in: &bag)
    }

    func applicationWillTerminate(_ notification: Notification) {
        media.stop()
        hud.stop()
    }

    // MARK: - Экраны

    private func targetScreens() -> [NSScreen] {
        switch themeStore.theme.behavior.displayMode {
        case .all:
            return NSScreen.screens
        case .main:
            return [NSScreen.main].compactMap { $0 }
        case .followMouse:
            return [NSScreen.withMouse ?? NSScreen.main].compactMap { $0 }
        case .notchedOrMain:
            return [NSScreen.withNotch ?? NSScreen.main].compactMap { $0 }
        }
    }

    private func rebuildIslands() {
        let screens = targetScreens()
        let wanted = Set(screens.map(\.displayID))

        for (id, controller) in controllers where !wanted.contains(id) {
            controller.close()
            controllers[id] = nil
        }

        for screen in screens {
            let id = screen.displayID
            if let existing = controllers[id] {
                existing.refreshScreenMetrics()
            } else {
                let controller = IslandController(
                    screen: screen,
                    media: media,
                    hud: hud,
                    themeStore: themeStore
                )
                controller.menu = buildMenu()
                controllers[id] = controller
            }
        }
    }

    /// Печатает, что мы «видим» на этой машине: экраны, вырез, источник музыки.
    private func dumpDiagnostics() {
        print("— LiquidIsland diagnostics —")
        for screen in NSScreen.screens {
            let m = NotchMetrics.measure(for: screen)
            print(String(
                format: "screen %@ %.0fx%.0f  notch: %@  notchSize: %.0fx%.0f  menuBar: %.0f  closed: %.0fx%.0f",
                screen.localizedName, screen.frame.width, screen.frame.height,
                m.hasHardwareNotch ? "yes" : "no",
                m.notchSize.width, m.notchSize.height, m.menuBarHeight,
                m.closedSize.width, m.closedSize.height
            ))
        }
        print("islands: \(controllers.count)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.controllers.values.first?.dumpHierarchy()
        }
        let glassClass = NSClassFromString("NSGlassEffectView")
        print("NSGlassEffectView: \(glassClass.map { "\($0)" } ?? "нет в системе")")
        if #available(macOS 26.0, *) {
            let probe = NSGlassEffectView()
            print("создаётся: \(type(of: probe)), стиль по умолчанию \(probe.style.rawValue)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            let np = self.media.nowPlaying
            print("provider: \(self.media.activeProviderName)")
            print("nowPlaying: '\(np.title)' — '\(np.artist)' playing=\(np.isPlaying) dur=\(Int(np.duration))")
            print("accent: \(np.accent.map { "\($0)" } ?? "нет")")
            print("audio tap: \(self.media.levels.isRunning ? "слушает" : "не запущен") bands=\(self.media.levels.bands)")
        }
    }

    // MARK: - Меню

    /// Иконка в меню-баре: капсула — буквально форма самого острова.
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "capsule.fill",
            accessibilityDescription: "LiquidIsland"
        )
        item.button?.image?.isTemplate = true
        item.menu = buildMenu()
        statusItem = item
    }

    /// То же меню открывается и правым кликом по самому острову.
    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "LiquidIsland", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Настройки…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        let config = NSMenuItem(
            title: "Открыть theme.json…",
            action: #selector(openConfig),
            keyEquivalent: ""
        )
        config.target = self
        menu.addItem(config)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Завершить",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        return menu
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(store: themeStore)
        }
        settingsWindow?.present()
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(themeStore.configURL)
    }

    @objc private func resetTheme() {
        themeStore.reset()
    }
}
