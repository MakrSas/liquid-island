import SwiftUI
import AppKit

/// Стекло острова.
///
/// Слоя два, и это намеренно. Нижний — `NSVisualEffectView`: он гарантированно
/// показывает размытую подложку, то есть даёт саму прозрачность. Верхний —
/// нативный `NSGlassEffectView` из macOS 26: он добавляет преломление, блик и
/// живёт по системным правилам прозрачности и контраста. Если система его
/// почему-то не рисует, стекло всё равно остаётся стеклом, а не чёрной дырой.
struct LiquidGlassView: NSViewRepresentable {
    var cornerRadius: CGFloat
    var isClear: Bool
    var tint: NSColor?
    var isInteractive: Bool

    func makeNSView(context: Context) -> NSView {
        let container = GlassContainerView()
        container.wantsLayer = true

        let blur = NSVisualEffectView()
        blur.material = isClear ? .underWindowBackground : .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.autoresizingMask = [.width, .height]
        container.addSubview(blur)
        container.blur = blur

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            // Содержимое должно занимать всю площадь: стекло считает
            // преломление по нему, и с пустым нулевым вью рисовать нечего.
            let content = NSView()
            content.wantsLayer = true
            content.autoresizingMask = [.width, .height]
            glass.contentView = content
            glass.autoresizingMask = [.width, .height]
            container.addSubview(glass)
            container.glass = glass
        }

        apply(to: container)
        return container
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let container = view as? GlassContainerView else { return }
        apply(to: container)
    }

    private func apply(to container: GlassContainerView) {
        container.cornerRadius = cornerRadius
        container.blur?.material = isClear ? .underWindowBackground : .hudWindow
        if #available(macOS 26.0, *), let glass = container.glass as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
            glass.style = isClear ? .clear : .regular
            glass.tintColor = tint
            if #available(macOS 27.0, *) {
                glass.effectIsInteractive = isInteractive
            }
        }
        container.needsLayout = true
    }
}

/// Держит слои стекла и следит, чтобы они повторяли форму и размер контейнера.
final class GlassContainerView: NSView {
    var blur: NSVisualEffectView?
    var glass: NSView?
    var cornerRadius: CGFloat = 0

    override func layout() {
        super.layout()
        blur?.frame = bounds
        glass?.frame = bounds
        blur?.layer?.cornerRadius = cornerRadius
        blur?.layer?.cornerCurve = .continuous
        blur?.layer?.masksToBounds = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }
}
