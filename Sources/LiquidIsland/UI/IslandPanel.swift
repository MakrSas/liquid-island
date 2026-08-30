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

    /// Панель обязана уметь становиться ключевой.
    ///
    /// `NSGlassEffectView` рисует настоящее жидкое стекло только в ключевом
    /// окне; в остальных оно вырождается в плоское размытие. Подменять геттер
    /// `isKeyWindow` бесполезно — состояние решает оконный сервер, а не мы.
    /// Стиль `nonactivatingPanel` при этом сохраняется: панель берёт ключ,
    /// не выводя всё приложение на передний план.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Хост-вью острова. Клики сквозь окно решаются не здесь, а переключением
/// `ignoresMouseEvents` у самой панели: так мимо острова проходит вообще всё,
/// включая события, до которых hitTest не добирается.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    /// Первый клик должен сразу доходить до содержимого.
    ///
    /// По умолчанию щелчок по неключевому окну тратится на то, чтобы сделать
    /// его ключевым, и до вью не доходит. Остров ключевым почти никогда не
    /// бывает, поэтому без этого каждое первое нажатие пропадало.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
