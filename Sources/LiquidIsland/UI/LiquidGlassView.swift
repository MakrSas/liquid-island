import AppKit
import ObjectiveC.runtime

/// Стекло острова, живущее в AppKit.
///
/// В SwiftUI его держать нельзя: backdrop-эффект композитится оконным сервером
/// и обрезку, заданную `clipShape`, игнорирует — вместо формы острова получается
/// прямоугольная полоса во всю ширину окна. Поэтому кадром и формой стекла
/// управляем сами, вручную.
final class IslandGlassView: NSView {

    private var glass: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        buildGlass()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    private func buildGlass() {
        guard #available(macOS 26.0, *) else { return }
        let view = NSGlassEffectView()
        // Стекло считает преломление по содержимому: пустое вью нулевого
        // размера означает, что рисовать нечего.
        let content = NSView()
        content.wantsLayer = true
        content.autoresizingMask = [.width, .height]
        view.contentView = content
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        glass = view
    }

    /// Форма и характер стекла.
    func configure(cornerRadius: CGFloat, isClear: Bool, tint: NSColor?, isInteractive: Bool) {
        guard #available(macOS 26.0, *), let glass = glass as? NSGlassEffectView else { return }
        glass.cornerRadius = cornerRadius
        glass.style = isClear ? .clear : .regular
        glass.tintColor = tint
        if #available(macOS 27.0, *) {
            glass.effectIsInteractive = isInteractive
        }
        awaken(glass)
    }

    /// Возвращает стеклу «бодрое» состояние.
    ///
    /// AppKit приглушает стекло, когда окно перестаёт быть ключевым: по
    /// `_windowChangedKeyState` выставляется `_subduedState`, и вместо
    /// преломления остаётся плоское размытие. Наша панель ключевой не бывает
    /// никогда, поэтому приглушение снимаем сами. Это единственный способ:
    /// открытого управления этим состоянием класс не даёт.
    private func awaken(_ view: NSView) {
        let selector = NSSelectorFromString("set_subduedState:")
        guard view.responds(to: selector) else { return }
        typealias Setter = @convention(c) (NSObject, Selector, Int) -> Void
        guard let method = class_getMethodImplementation(type(of: view), selector) else { return }
        let setter = unsafeBitCast(method, to: Setter.self)
        setter(view, selector, 0)
    }

    override func layout() {
        super.layout()
        glass?.frame = bounds
        // AppKit приглушает стекло при каждой смене состояния окна,
        // поэтому снимаем приглушение и здесь, а не только при настройке.
        if let glass { awaken(glass) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let glass { awaken(glass) }
    }

    /// Клики сквозь стекло проходят к острову.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
