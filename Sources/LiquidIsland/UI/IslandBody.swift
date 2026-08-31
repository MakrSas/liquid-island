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
    /// Сколько всего активностей и какая показана — под них рисуются точки.
    var pageCount: Int = 0
    var pageIndex: Int = 0
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

            // Точки внизу — как в постраничном просмотре: видно, что активностей
            // несколько, и какая из них сейчас открыта.
            if pageCount > 1 {
                pageDots
                    .frame(width: size.width, height: size.height, alignment: .bottom)
                    .padding(.bottom, 3)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var pageDots: some View {
        HStack(spacing: 4) {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .fill(theme.palette.primaryText.color)
                    .opacity(index == pageIndex ? 0.9 : 0.3)
                    .frame(width: 4, height: 4)
            }
        }
        .animation(theme.motion.content, value: pageIndex)
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
            // Без своего перехода SwiftUI подставляет затухание, и карточка
            // мигает вместо того, чтобы перетекать вместе с островом.
            .transition(.identity)
        } else {
            // Без музыки остров — просто чёрное пятно, неотличимое от выреза.
            Color.clear
        }
    }
}
