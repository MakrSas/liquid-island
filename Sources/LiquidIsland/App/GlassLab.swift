import AppKit

/// Стенд для сравнения вариантов стекла.
///
/// Нужен, чтобы перестать спорить о словах: в одном обычном окне рядом лежат
/// несколько `NSGlassEffectView` с разными настройками и один
/// `NSVisualEffectView` для сравнения. Видно, какой из них выглядит стеклом,
/// а какой размытием, и отличается ли поведение от нашей панели.
@MainActor
enum GlassLab {

    static func open() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Стенд стекла"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.center()

        let root = NSView(frame: window.contentLayoutRect)
        root.autoresizingMask = [.width, .height]
        window.contentView = root

        var samples: [(String, NSView)] = []
        if #available(macOS 26.0, *) {
            samples = [
                ("clear r=20\nпустой", glass(style: .clear, radius: 20, filled: false)),
                ("clear r=20\nс содержимым", glass(style: .clear, radius: 20, filled: true)),
                ("regular r=20", glass(style: .regular, radius: 20, filled: true)),
                ("clear r=64\nкапсула", glass(style: .clear, radius: 64, filled: true)),
                ("NSVisualEffectView\n(это точно блюр)", blur())
            ]
        }

        let columns = samples.count
        let gap: CGFloat = 16
        let width = (900 - gap * CGFloat(columns + 1)) / CGFloat(columns)

        for (index, sample) in samples.enumerated() {
            let x = gap + (width + gap) * CGFloat(index)
            sample.1.frame = NSRect(x: x, y: 120, width: width, height: 128)
            sample.1.autoresizingMask = [.minXMargin, .maxXMargin]
            root.addSubview(sample.1)

            let label = NSTextField(labelWithString: sample.0)
            label.frame = NSRect(x: x, y: 60, width: width, height: 44)
            label.alignment = .center
            label.font = .systemFont(ofSize: 11)
            label.maximumNumberOfLines = 3
            root.addSubview(label)
        }

        let hint = NSTextField(labelWithString:
            "Подвинь окно на обои или на видео — стекло должно преломлять то, что под ним.")
        hint.frame = NSRect(x: 20, y: 20, width: 860, height: 20)
        hint.alignment = .center
        hint.font = .systemFont(ofSize: 12)
        root.addSubview(hint)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        retained = window
    }

    private static var retained: NSWindow?

    @available(macOS 26.0, *)
    private static func glass(
        style: NSGlassEffectView.Style,
        radius: CGFloat,
        filled: Bool
    ) -> NSView {
        let view = NSGlassEffectView()
        view.style = style
        view.cornerRadius = radius
        if #available(macOS 27.0, *) { view.effectIsInteractive = true }

        let content = NSView()
        content.wantsLayer = true
        content.autoresizingMask = [.width, .height]
        if filled {
            // Что-то видимое внутри: проверяем, влияет ли содержимое на эффект.
            let label = NSTextField(labelWithString: "Aa")
            label.font = .systemFont(ofSize: 28, weight: .semibold)
            label.frame = NSRect(x: 16, y: 44, width: 80, height: 40)
            content.addSubview(label)
        }
        view.contentView = content
        return view
    }

    private static func blur() -> NSView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 20
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }
}
