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

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Держим делегата живым на всё время работы приложения.
        objc_setAssociatedObject(app, "liquid.island.delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        app.run()
    }
}
