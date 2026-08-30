import SwiftUI
import AppKit

/// Мост к нативному Liquid Glass macOS 26+.
///
/// Это тот же эффект, что у системных панелей: он сам подхватывает настройки
/// прозрачности и контраста из «Универсального доступа», сам реагирует на
/// содержимое под собой. Своими руками такое не рисуется, поэтому на системах
/// старше 26 просто уступаем место обычному размытию.
struct LiquidGlassView: NSViewRepresentable {
    var cornerRadius: CGFloat
    var isClear: Bool
    var tint: NSColor?
    var isInteractive: Bool

    func makeNSView(context: Context) -> NSView {
        guard #available(macOS 26.0, *) else {
            let fallback = NSVisualEffectView()
            fallback.material = .hudWindow
            fallback.blendingMode = .behindWindow
            fallback.state = .active
            fallback.wantsLayer = true
            fallback.layer?.cornerCurve = .continuous
            return fallback
        }
        let view = NSGlassEffectView()
        // Без contentView стекло рисует одну лишь подложку и выглядит блюром:
        // краевое преломление и блик считаются по содержимому.
        let content = NSView()
        content.wantsLayer = true
        view.contentView = content
        apply(to: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            apply(to: glass)
        } else {
            view.layer?.cornerRadius = cornerRadius
        }
    }

    @available(macOS 26.0, *)
    private func apply(to view: NSGlassEffectView) {
        view.cornerRadius = cornerRadius
        view.style = isClear ? .clear : .regular
        view.tintColor = tint
        if #available(macOS 27.0, *) {
            view.effectIsInteractive = isInteractive
        }
    }
}
