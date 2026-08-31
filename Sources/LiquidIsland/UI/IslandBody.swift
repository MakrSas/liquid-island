import SwiftUI

/// Тело острова: подложка, кромка и содержимое.
///
/// Один и тот же вид используют и настоящий остров, и превью в настройках —
/// иначе превью неизбежно разойдётся с оригиналом, как только что-нибудь
/// поменяется. Всё, что зависит от окна и мыши, живёт снаружи.
struct IslandBody: View {
    @ObservedObject var media: MediaHub
    let theme: IslandTheme
    let phase: IslandPhase
    let size: CGSize
    let shapeStyle: IslandShape.Style
    /// Показывать ли карточку трека вместо пустой пилюли.
    let showsMedia: Bool
    var levels: [Float] = []
    /// Плашка системного события, если она сейчас важнее трека.
    var hudEvent: SystemEvent?
    /// Сдвиг и прозрачность на свайпе.
    var swipeOffset: CGFloat = 0
    var swipeFade: Double = 1

    var shape: IslandShape {
        IslandShape(
            style: shapeStyle,
            topRadius: theme.geometry.topRadius,
            bottomRadius: phase == .expanded || showsMedia || hudEvent != nil
                ? (phase == .expanded
                   ? theme.geometry.bottomRadiusOpen
                   : theme.geometry.bottomRadiusClosed)
                : theme.geometry.bottomRadiusClosed
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

    var body: some View {
        ZStack {
            IslandBackground(
                shape: shape,
                theme: theme,
                glassReveal: phase == .expanded ? 1 : 0
            )
            .overlay(
                shape
                    .strokeBorder(rimGradient, lineWidth: theme.palette.rimWidth)
                    .opacity(showsMedia || phase != .closed ? 1 : 0)
            )

            content
                // Прижимаем к верху: если высоты не хватает, обрезаться должен
                // низ, а не обложка с названием.
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipped()
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private var content: some View {
        if let hudEvent {
            if case .lowBattery(let charge) = hudEvent {
                BatteryWarningView(charge: charge, theme: theme)
                    .padding(theme.geometry.contentPadding)
                    .transition(.softFade(scale: 0.9, offsetY: 0))
            } else {
                HUDView(event: hudEvent, theme: theme)
                    .padding(theme.geometry.compactPadding)
                    .transition(.softFade(scale: 0.9, offsetY: 0))
            }
        } else if showsMedia || (phase == .expanded && !media.nowPlaying.isEmpty) {
            IslandMediaView(
                media: media,
                theme: theme,
                phase: phase,
                levels: levels
            )
            .offset(x: swipeOffset)
            .opacity(swipeFade)
        } else {
            // Без музыки остров — просто чёрное пятно, неотличимое от выреза.
            Color.clear
        }
    }
}
