import AppKit

@main
enum LiquidIslandApp {
    @MainActor
    static func main() {
        setbuf(stdout, nil)
        // Режим рендера превью: рисуем PNG и выходим, интерфейс не поднимаем.
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--render-preview") {
            let path = index + 1 < args.count ? args[index + 1] : "./preview"
            // ImageRenderer тянет за собой AppKit — окно не показываем,
            // но само приложение инициализировать обязаны.
            _ = NSApplication.shared
            PreviewRenderer.renderAll(to: URL(fileURLWithPath: path))
            return
        }

        if args.contains("--glass-lab") {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            let delegate = GlassLabDelegate()
            app.delegate = delegate
            objc_setAssociatedObject(app, "liquid.island.lab", delegate, .OBJC_ASSOCIATION_RETAIN)
            app.run()
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Держим делегата живым на всё время работы приложения.
        objc_setAssociatedObject(app, "liquid.island.delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        app.run()
    }
}

/// Поднимает только стенд стекла, без острова.
@MainActor
final class GlassLabDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        GlassLab.open()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
