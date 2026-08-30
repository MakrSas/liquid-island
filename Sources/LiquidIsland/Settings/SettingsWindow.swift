import AppKit
import SwiftUI

/// Окно настроек.
///
/// Обычное окно с боковой панелью — то же, что у системных Настроек:
/// объединённый заголовок, скрытый разделитель, размер запоминается системой.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    convenience init(store: ThemeStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Настройки LiquidIsland"
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        // Размер и положение запоминаются между запусками — как у любого
        // обычного окна macOS.
        window.setFrameAutosaveName("LiquidIslandSettings")
        window.contentView = NSHostingView(rootView: SettingsView(store: store))
        window.center()

        self.init(window: window)
        window.delegate = self
    }

    /// Показывает окно и выводит приложение вперёд: без иконки в Dock оно
    /// иначе откроется позади всего.
    func present() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Возвращаемся в фон: остров — приложение без Dock-иконки.
        NSApp.setActivationPolicy(.accessory)
    }
}
