import AppKit
import SwiftUI

/// Рендерит остров в PNG без запуска интерфейса.
///
/// Нужен для быстрой сверки дизайна: правишь тему — сразу видишь картинку,
/// не гоняя приложение и не делая скриншотов экрана.
@MainActor
enum PreviewRenderer {

    static func renderAll(to directory: URL, theme: IslandTheme = ThemeStore.shared.theme) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let sample = NowPlaying(
            title: "Come to Life",
            artist: "Refuzion & Serzo",
            album: "Come to Life",
            artwork: placeholderArtwork(),
            duration: 182,
            elapsed: 136,
            isPlaying: true,
            sourceBundleID: nil
        )

        for style in [IslandShape.Style.floating, .notch] {
            let suffix = style == .notch ? "notch" : "floating"
            render(
                view: closedPill(theme: theme, style: style),
                size: sizeFor(theme.geometry.closedSize),
                to: directory.appendingPathComponent("closed-\(suffix).png")
            )
            render(
                view: shell(theme: theme, style: style, size: theme.geometry.compactSize) {
                    CompactMediaView(track: sample, theme: theme)
                },
                size: sizeFor(theme.geometry.compactSize),
                to: directory.appendingPathComponent("activity-\(suffix).png")
            )
            render(
                view: shell(theme: theme, style: style, size: theme.geometry.expandedSize) {
                    ExpandedMediaView(media: StubHub(track: sample), theme: theme)
                },
                size: sizeFor(theme.geometry.expandedSize),
                to: directory.appendingPathComponent("expanded-\(suffix).png")
            )
        }
    }

    // Поле вокруг острова, чтобы на картинке была видна его форма и тень.
    private static func sizeFor(_ size: CGSize) -> CGSize {
        CGSize(width: size.width + 80, height: size.height + 60)
    }

    private static func closedPill(theme: IslandTheme, style: IslandShape.Style) -> some View {
        shell(theme: theme, style: style, size: theme.geometry.closedSize) { Color.clear }
    }

    private static func shell<Content: View>(
        theme: IslandTheme,
        style: IslandShape.Style,
        size: CGSize,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let radius = size.height > theme.geometry.closedSize.height + 1
            ? theme.geometry.bottomRadiusOpen
            : theme.geometry.bottomRadiusClosed
        let shape = IslandShape(
            style: style,
            topRadius: theme.geometry.topRadius,
            bottomRadius: radius
        )
        return ZStack {
            // Условный «рабочий стол», чтобы чёрное было видно на превью.
            LinearGradient(
                colors: [Color(white: 0.42), Color(white: 0.24)],
                startPoint: .top, endPoint: .bottom
            )
            VStack(spacing: 0) {
                ZStack {
                    shape.fill(theme.palette.background.color)
                    shape.strokeBorder(theme.palette.rimLight.color, lineWidth: 0.5)
                    content()
                        .padding(theme.geometry.contentPadding)
                        .frame(width: size.width, height: size.height)
                }
                .frame(width: size.width, height: size.height)
                .padding(.top, style == .notch ? 0 : theme.geometry.floatingTopInset)
                Spacer(minLength: 0)
            }
        }
    }

    private static func render(view: some View, size: CGSize, to url: URL) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        // Кодируем сами: ImageIO на этой сборке macOS падает при записи
        // изображения из процесса без интерфейса.
        guard let cgImage = renderer.cgImage else {
            print("render failed (no image): \(url.lastPathComponent)")
            return
        }
        guard let png = PNGEncoder.encode(cgImage) else {
            print("render failed (no png): \(url.lastPathComponent)")
            return
        }
        try? png.write(to: url)
        print("rendered \(url.lastPathComponent)")
    }

    private static func placeholderArtwork() -> NSImage {
        let size = NSSize(width: 200, height: 200)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(
            colors: [
                NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.25, alpha: 1),
                NSColor(calibratedRed: 0.35, green: 0.20, blue: 0.55, alpha: 1)
            ]
        )?.draw(in: NSRect(origin: .zero, size: size), angle: -45)
        image.unlockFocus()
        return image
    }
}

/// Неизменный источник данных — только для превью.
@MainActor
private final class StubHub: MediaHub {
    init(track: NowPlaying) {
        super.init()
        stop()
        setPreviewTrack(track)
    }
}
