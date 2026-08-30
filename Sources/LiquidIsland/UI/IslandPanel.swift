import AppKit
import SwiftUI

/// Прозрачное окно, которое живёт поверх меню-бара и не забирает фокус.
final class IslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .init(Int(CGWindowLevelForKey(.statusWindow)) + 2)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        // Остров должен быть виден и на других рабочих столах, и поверх
        // полноэкранных приложений — как настоящая чёлка.
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        // Не участвуем в Cmd-Tab и не мешаем окнам-приложениям.
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    /// Панель выдаёт себя за активную, хотя фокус не берёт.
    ///
    /// `NSGlassEffectView` рисует настоящее жидкое стекло только в активном
    /// окне: в неактивном оно вырождается в плоское размытие. Наша панель
    /// ключевой не становится никогда, поэтому без этой подмены стекло
    /// выглядело бы блюром при любых настройках.
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

/// Хост-вью острова. Клики сквозь окно решаются не здесь, а переключением
/// `ignoresMouseEvents` у самой панели: так мимо острова проходит вообще всё,
/// включая события, до которых hitTest не добирается.
final class IslandHostingView<Content: View>: NSHostingView<Content> {}
