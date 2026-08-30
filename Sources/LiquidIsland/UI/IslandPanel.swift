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
}

/// Хост-вью, который пропускает клики мимо себя везде, где остров прозрачен.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    /// Прямоугольник (в координатах вью), внутри которого мы ловим мышь.
    var interactiveRect: CGRect = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveRect.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }
}
