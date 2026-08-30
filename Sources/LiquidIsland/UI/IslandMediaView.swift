import SwiftUI

/// Единственный макет карточки на все фазы.
///
/// Ключ к настоящему переходу — не подменять одну вьюху другой, а менять
/// параметры одной и той же. Обложка не исчезает и не появляется, а растёт;
/// заголовок едет на новое место; строки прогресса и кнопок не вставляются
/// в иерархию, а разворачиваются по высоте из нуля. Тогда SwiftUI
/// интерполирует кадры, и остров перетекает, а не мигает.
///
/// Своей анимации здесь нет намеренно: движение ведёт та же пружина, что
/// меняет размер острова. Вторая анимация поверх неё разводит кадр и
/// содержимое по разным кривым, и переход рассыпается.
struct IslandMediaView: View {
    @ObservedObject var media: MediaHub
    let theme: IslandTheme
    let phase: IslandPhase
    var levels: [Float] = []

    private var track: NowPlaying { media.nowPlaying }
    private var isExpanded: Bool { phase == .expanded }
    private var isHovered: Bool { phase == .hovered }

    // MARK: - Параметры, которые перетекают

    private var artworkSize: CGFloat {
        isExpanded ? 56 : (isHovered ? 34 : 18)
    }

    private var artworkRadius: CGFloat {
        isExpanded ? 12 : (isHovered ? theme.geometry.artworkRadiusHovered : theme.geometry.artworkRadius)
    }

    /// Шрифт масштабируем, а не подменяем: смена размера шрифта в SwiftUI
    /// не интерполируется и даёт скачок.
    private var titleScale: CGFloat {
        isExpanded ? 1.18 : (isHovered ? 1.09 : 1)
    }

    private var showsArtist: Bool { isExpanded || isHovered }
    private var waveHeight: CGFloat { isExpanded ? 16 : (isHovered ? 14 : 10) }

    private var padding: EdgeInsets {
        isExpanded ? theme.geometry.contentPadding : theme.geometry.compactPadding
    }

    private var accentColor: Color {
        track.accent.map(Color.init) ?? theme.palette.primaryText.color.opacity(0.9)
    }

    var body: some View {
        VStack(spacing: isExpanded ? 10 : 0) {
            header
            progressRow
            transportRow
        }
        .padding(padding)
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(spacing: isExpanded ? 12 : 8) {
            ArtworkView(image: track.artwork, size: artworkSize, cornerRadius: artworkRadius)

            VStack(alignment: .leading, spacing: showsArtist ? 2 : 0) {
                Text(track.title.isEmpty ? "Ничего не играет" : track.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.palette.primaryText.color)
                    .lineLimit(1)
                    .scaleEffect(titleScale, anchor: .leading)

                Text(track.artist)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.palette.secondaryText.color)
                    .lineLimit(1)
                    .scaleEffect(isExpanded ? 1.08 : 1, anchor: .leading)
                    .frame(height: showsArtist && !track.artist.isEmpty ? 13 : 0)
                    .opacity(showsArtist && !track.artist.isEmpty ? 1 : 0)
                    .clipped()
            }

            Spacer(minLength: 6)

            WaveformView(
                isPlaying: track.isPlaying,
                color: accentColor,
                levels: levels,
                height: waveHeight
            )
        }
    }

    // MARK: - Прогресс

    private var progressRow: some View {
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
        .frame(height: isExpanded ? 24 : 0)
        .opacity(isExpanded ? 1 : 0)
        .clipped()
    }

    // MARK: - Кнопки

    private var transportRow: some View {
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
        .opacity(isExpanded && track.supportsTransport ? 1 : 0)
        .allowsHitTesting(isExpanded && track.supportsTransport)
        .frame(height: isExpanded ? 36 : 0)
        .clipped()
    }

    private static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
