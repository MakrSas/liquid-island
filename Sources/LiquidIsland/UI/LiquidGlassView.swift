import SwiftUI
import AppKit

/// Нативное жидкое стекло macOS 26.
///
/// Без подложек: `NSVisualEffectView`, положенный снизу, перебивает эффект
/// своим размытием, и в итоге видно именно его, а не стекло. Здесь только
/// `NSGlassEffectView` — либо он рисует стекло, либо не рисует ничего, и это
/// сразу видно.
struct LiquidGlassView: NSViewRepresentable {
    var cornerRadius: CGFloat
    var isClear: Bool
    var tint: NSColor?
    var isInteractive: Bool

    func makeNSView(context: Context) -> NSView {
        guard #available(macOS 26.0, *) else {
            let fallback = NSVisualEffectView()
            fallback.material = .underWindowBackground
            fallback.blendingMode = .behindWindow
            fallback.state = .active
            return fallback
        }

        let glass = NSGlassEffectView()
        // Стекло считает преломление по содержимому: пустое вью нулевого
        // размера означает, что рисовать нечего.
        let content = NSView()
        content.wantsLayer = true
        content.autoresizingMask = [.width, .height]
        glass.contentView = content
        apply(to: glass)
        return glass
    }

    func updateNSView(_ view: NSView, context: Context) {
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            apply(to: glass)
            glass.contentView?.frame = glass.bounds
        }
    }

    @available(macOS 26.0, *)
    private func apply(to glass: NSGlassEffectView) {
        glass.cornerRadius = cornerRadius
        glass.style = isClear ? .clear : .regular
        glass.tintColor = tint
        if #available(macOS 27.0, *) {
            glass.effectIsInteractive = isInteractive
        }
    }
}
