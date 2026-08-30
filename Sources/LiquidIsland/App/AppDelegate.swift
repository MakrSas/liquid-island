import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let media = MediaHub()
    private let themeStore = ThemeStore.shared
    private var controllers: [CGDirectDisplayID: IslandController] = [:]
    private var statusItem: NSStatusItem?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Приложение без Dock-иконки: остров — это и есть весь интерфейс.
        NSApp.setActivationPolicy(.accessory)

        media.start()
        rebuildIslands()
        installStatusItem()
        if ProcessInfo.processInfo.environment["LIQUID_ISLAND_DEBUG"] == "1" { dumpDiagnostics() }

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildIslands() }
            .store(in: &bag)

        themeStore.$theme
            .map(\.behavior.displayMode)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.rebuildIslands() }
            .store(in: &bag)
    }

    func applicationWillTerminate(_ notification: Notification) {
        media.stop()
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
                controllers[id] = IslandController(screen: screen, media: media, themeStore: themeStore)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            let np = self.media.nowPlaying
            print("provider: \(self.media.activeProviderName)")
            print("nowPlaying: '\(np.title)' — '\(np.artist)' playing=\(np.isPlaying) dur=\(Int(np.duration))")
        }
    }

    // MARK: - Меню в статус-баре

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "drop.fill",
            accessibilityDescription: "LiquidIsland"
        )
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: "LiquidIsland", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let config = NSMenuItem(
            title: "Открыть theme.json…",
            action: #selector(openConfig),
            keyEquivalent: ","
        )
        config.target = self
        menu.addItem(config)

        let reset = NSMenuItem(
            title: "Сбросить оформление",
            action: #selector(resetTheme),
            keyEquivalent: ""
        )
        reset.target = self
        menu.addItem(reset)

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Завершить",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(themeStore.configURL)
    }

    @objc private func resetTheme() {
        themeStore.reset()
    }
}
