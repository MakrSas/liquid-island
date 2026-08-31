import SwiftUI

/// Живое превью острова в настройках.
///
/// Показывает не копию, а тот же самый `IslandBody`, что рисует настоящий
/// остров, — иначе превью разошлось бы с оригиналом при первой же правке.
/// Фон — обои рабочего стола: на сером стекло не читается, а именно его и
/// нужно оценивать. Стекло здесь настоящее: окно настроек ключевое, значит
/// система рисует его полноценно.
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

    private var island: IslandBody {
        IslandBody(
            media: media,
            track: media.nowPlaying,
            theme: theme,
            phase: phase,
            size: size,
            shapeStyle: .notch,
            showsMedia: true,
            levels: [0.85, 0.4, 0.7, 0.3]
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Стекло лежит здесь всегда, а не появляется при раскрытии:
            // вставка и удаление вью читаются затуханием, а не перетеканием.
            // В покое его полностью закрывает чёрное тело острова — так же,
            // как в настоящем острове.
            if #available(macOS 26.0, *), theme.palette.useLiquidGlass {
                Color.clear
                    .frame(width: size.width, height: size.height)
                    .glassEffect(glass, in: island.shape)
            }
            island
        }
        // Высота с запасом: раскрытый остров помещается целиком, под ним
        // остаётся видимая полоса обоев. Выравнивание обязательно в той же
        // рамке, где задана высота, иначе содержимое встанет по центру.
        .frame(
            maxWidth: .infinity,
            minHeight: theme.geometry.expandedSize.height + 56,
            maxHeight: theme.geometry.expandedSize.height + 56,
            alignment: .top
        )
        // Обои именно фоном: как участник разметки картинка задаёт размер
        // контейнера и выталкивает остров за видимую область.
        .background { Wallpaper() }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(theme.motion.open, value: phase)
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        let base: Glass = theme.palette.glassStyle == .clear ? .clear : .regular
        guard let tint = theme.palette.glassTint else { return base }
        return base.tint(tint.color)
    }
}

/// Обои рабочего стола, а если их не достать — системные, которые есть на
/// каждом маке. Так превью выглядит одинаково и не упирается в пустой фон.
private struct Wallpaper: View {
    private var image: NSImage? {
        if let screen = NSScreen.main,
           let url = NSWorkspace.shared.desktopImageURL(for: screen),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(contentsOfFile: "/System/Library/CoreServices/DefaultDesktop.heic")
    }

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(
                colors: [Color(nsColor: .systemBlue), Color(nsColor: .systemTeal)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
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
