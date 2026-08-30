import SwiftUI

struct IslandRootView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var media: MediaHub
    @ObservedObject var themeStore: ThemeStore = .shared
    @ObservedObject var audio: AudioLevels

    private var theme: IslandTheme { themeStore.theme }
    private var size: CGSize { state.size }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // По умолчанию ноль: остров врастает в кромку экрана, а не висит под ней.
        .padding(.top, theme.geometry.floatingTopInset)
    }

    private var shape: IslandShape {
        IslandShape(
            style: state.shapeStyle,
            topRadius: theme.geometry.topRadius,
            bottomRadius: state.bottomRadius
        )
    }

    /// Кромка стекла: сверху блик, снизу почти ничего — так объём читается
    /// даже на чёрном.
    private var rimGradient: LinearGradient {
        LinearGradient(
            colors: [
                theme.palette.rimLight.color,
                theme.palette.rimLight.color.opacity(0.15)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var island: some View {
        ZStack {
            IslandBackground(
                shape: shape,
                theme: theme,
                glassReveal: state.phase == .expanded ? 1 : 0
            )
            .overlay(
                shape
                    .strokeBorder(rimGradient, lineWidth: theme.palette.rimWidth)
                    .opacity(state.showsMediaCard || state.phase != .closed ? 1 : 0)
            )

            content
                .padding(state.phase == .expanded
                         ? theme.geometry.contentPadding
                         : theme.geometry.compactPadding)
                .frame(width: size.width, height: size.height)
                .clipped()
        }
        .frame(width: size.width, height: size.height)
        .shadow(
            color: .black.opacity(state.phase == .expanded ? 0.45 : 0),
            radius: 22, x: 0, y: 10
        )
        .contentShape(shape)
        // Наведение отслеживает IslandController: окно почти всё время
        // сквозное, и SwiftUI о движениях мыши просто не узнаёт.
        .onTapGesture { state.toggle() }
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .closed, .hovered:
            if state.showsMediaCard {
                CompactMediaView(
                    track: media.nowPlaying,
                    theme: theme,
                    levels: audio.bands,
                    showsArtist: state.phase == .hovered
                )
                .transition(.blurFade(radius: 6))
                // Свайп по тачпаду уводит карточку вбок.
                .offset(x: state.swipeOffset)
                .opacity(state.swipeFade)
            } else {
                // Без музыки остров — просто чёрное пятно, неотличимое от выреза.
                Color.clear
            }
        case .expanded:
            ExpandedMediaView(media: media, theme: theme, levels: audio.bands)
                .transition(.blurFade(radius: 10))
        }
    }
}

// MARK: - Компактный вид

struct CompactMediaView: View {
    let track: NowPlaying
    let theme: IslandTheme
    var levels: [Float] = []
    /// В покое карточка ровно по высоте пилюли — на вторую строку места нет.
    /// Она появляется, когда остров подрастает под курсором.
    var showsArtist: Bool = false

    private var artworkRadius: CGFloat {
        showsArtist ? theme.geometry.artworkRadiusHovered : theme.geometry.artworkRadius
    }

    /// Цвет обложки, если его удалось вытянуть, иначе обычный белый.
    private var accentColor: Color {
        track.accent.map(Color.init) ?? theme.palette.primaryText.color.opacity(0.9)
    }

    var body: some View {
        HStack(spacing: 8) {
            ArtworkView(
                image: track.artwork,
                size: showsArtist ? 34 : 18,
                cornerRadius: artworkRadius
            )
            .id(track.title)
            .transition(.blurFade(radius: 10, scale: 0.7))
            .animation(theme.motion.content, value: track.title)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title.isEmpty ? "Ничего не играет" : track.title)
                    .font(.system(size: showsArtist ? 12 : 11, weight: .semibold))
                    .foregroundStyle(theme.palette.primaryText.color)
                    .lineLimit(1)
                    .id(track.title)
                    .transition(.blurFade(radius: 6))
                if showsArtist, !track.artist.isEmpty {
                    Text(track.artist)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.palette.secondaryText.color)
                        .lineLimit(1)
                        .id(track.artist)
                        .transition(.blurFade(radius: 6))
                }
            }
            .animation(theme.motion.content, value: track.title)
            Spacer(minLength: 6)
            WaveformView(
                isPlaying: track.isPlaying,
                color: accentColor,
                levels: levels,
                height: showsArtist ? 14 : 10
            )
        }
    }
}

// MARK: - Раскрытый вид

struct ExpandedMediaView: View {
    @ObservedObject var media: MediaHub
    let theme: IslandTheme
    var levels: [Float] = []

    private var track: NowPlaying { media.nowPlaying }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ArtworkView(image: track.artwork, size: 56, cornerRadius: 12)

                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(
                        text: track.title.isEmpty ? "Ничего не играет" : track.title,
                        font: .system(size: 13, weight: .semibold),
                        color: theme.palette.primaryText.color
                    )
                    MarqueeText(
                        text: track.artist.isEmpty ? media.activeProviderName : track.artist,
                        font: .system(size: 11, weight: .medium),
                        color: theme.palette.secondaryText.color
                    )
                }

                Spacer(minLength: 4)

                WaveformView(
                    isPlaying: track.isPlaying,
                    color: track.accent.map(Color.init)
                        ?? theme.palette.primaryText.color.opacity(0.85),
                    levels: levels,
                    barCount: 4,
                    height: 16
                )
            }

            VStack(spacing: 4) {
                ProgressBarView(
                    progress: track.progress,
                    trackColor: theme.palette.progressTrack.color,
                    fillColor: theme.palette.progressFill.color
                )
                HStack {
                    Text(Self.format(track.elapsed))
                        .contentTransition(.numericText())
                    Spacer()
                    Text("-" + Self.format(max(track.duration - track.elapsed, 0)))
                        .contentTransition(.numericText())
                }
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(theme.palette.secondaryText.color)
                .animation(.easeInOut(duration: 0.35), value: Int(track.elapsed))
            }

            HStack(spacing: 20) {
                TransportButton(systemName: "backward.fill", size: 15) {
                    media.send(.previous)
                }
                TransportButton(
                    systemName: track.isPlaying ? "pause.fill" : "play.fill",
                    size: 19
                ) {
                    media.send(.playPause)
                }
                TransportButton(systemName: "forward.fill", size: 15) {
                    media.send(.next)
                }
            }
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
