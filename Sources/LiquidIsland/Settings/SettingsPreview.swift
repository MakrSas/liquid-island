import SwiftUI

/// Живое превью острова внутри настроек.
///
/// Показывает ровно те же вьюхи, что и настоящий остров, поэтому любая правка
/// видна сразу и не требует раскрывать остров на экране. Стекла здесь нет:
/// оно рисуется системой только в ключевом окне и в превью выглядело бы
/// иначе, чем на самом деле, — лучше честно показать чёрное тело.
struct SettingsPreview: View {
    @ObservedObject var store: ThemeStore
    let phase: IslandPhase
    @StateObject private var media = PreviewHub()

    private var theme: IslandTheme { store.theme }

    private var size: CGSize {
        switch phase {
        case .closed: return theme.geometry.compactSize
        case .hovered:
            return CGSize(
                width: theme.geometry.compactSize.width + theme.geometry.hoverPadding.width,
                height: theme.geometry.compactSize.height + theme.geometry.hoverPadding.height
            )
        case .expanded: return theme.geometry.expandedSize
        }
    }

    private var shape: IslandShape {
        IslandShape(
            style: .notch,
            topRadius: theme.geometry.topRadius,
            bottomRadius: phase == .expanded
                ? theme.geometry.bottomRadiusOpen
                : theme.geometry.bottomRadiusClosed
        )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(nsColor: .controlBackgroundColor), Color(nsColor: .windowBackgroundColor)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                ZStack {
                    shape.fill(theme.palette.background.color)
                    shape.strokeBorder(
                        theme.palette.rimLight.color,
                        lineWidth: theme.palette.rimWidth
                    )
                    IslandMediaView(
                        media: media,
                        theme: theme,
                        phase: phase,
                        levels: [0.85, 0.4, 0.7, 0.3]
                    )
                    .frame(width: size.width, height: size.height)
                    .clipped()
                }
                .frame(width: size.width, height: size.height)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: theme.geometry.expandedSize.height + 24)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(theme.motion.open, value: phase)
    }
}

/// Неподвижный источник для превью: настоящий опрос здесь не нужен.
@MainActor
private final class PreviewHub: MediaHub {
    override init() {
        super.init()
        setPreviewTrack(
            NowPlaying(
                title: "Come to Life",
                artist: "Refuzion & Serzo",
                album: "",
                artwork: PreviewHub.artwork(),
                duration: 182,
                elapsed: 136,
                isPlaying: true,
                sourceBundleID: nil
            )
        )
    }

    private static func artwork() -> NSImage {
        let size = NSSize(width: 160, height: 160)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(colors: [
            NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.25, alpha: 1),
            NSColor(calibratedRed: 0.35, green: 0.20, blue: 0.55, alpha: 1)
        ])?.draw(in: NSRect(origin: .zero, size: size), angle: -45)
        image.unlockFocus()
        return image
    }
}
