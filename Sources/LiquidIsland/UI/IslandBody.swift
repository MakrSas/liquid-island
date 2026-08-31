import SwiftUI

/// Тело острова: подложка, кромка и содержимое.
///
/// Один и тот же вид используют и настоящий остров, и превью в настройках —
/// иначе превью неизбежно разойдётся с оригиналом, как только что-нибудь
/// поменяется. Всё, что зависит от окна и мыши, живёт снаружи.
struct IslandBody: View {
    @ObservedObject var media: MediaHub
    /// Какой источник показываем. Их может быть несколько, и выбирает
    /// пользователь листанием.
    let track: NowPlaying
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
    /// Воспроизведение стоит — обложку приглушаем.
    var isDimmed: Bool = false
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

            // Точки — как в постраничном просмотре: видно, что активностей
            // несколько, и какая из них открыта. В пустом острове их нет:
            // показывать нечего, а пилюля должна оставаться чёрным пятном.
            if showsDots, theme.behavior.dotsPlacement == .inside {
                pageDots
                    .frame(width: size.width, height: size.height, alignment: .bottom)
                    .padding(.bottom, theme.geometry.dotsInset)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Капсула с точками под островом — второй вариант размещения.
    @ViewBuilder
    var dotsCapsule: some View {
        if showsDots, theme.behavior.dotsPlacement == .below {
            pageDots
                .frame(width: dotsCapsuleWidth, height: theme.geometry.dotsCapsuleHeight)
                .background {
                    // Стекло система рисует полноценным только в ключевом
                    // окне, то есть когда остров раскрыт. В остальное время
                    // капсула чёрная: полустеклянная выглядела бы поломкой.
                    if #available(macOS 26.0, *),
                       theme.palette.useLiquidGlass,
                       phase == .expanded {
                        Capsule().fill(.clear).glassEffect(glass, in: Capsule())
                    } else {
                        Capsule().fill(theme.palette.background.color)
                    }
                }
                .padding(.top, theme.geometry.dotsCapsuleGap)
                // Уходит вверх, под остров, а не вбок: по умолчанию SwiftUI
                // уводит вьюху туда, куда сожмётся разметка, и капсула
                // уезжала вправо.
                .transition(
                    .move(edge: .top)
                        .combined(with: .opacity)
                        .combined(with: .scale(scale: 0.8, anchor: .top))
                )
                // Ширина полосы не зависит от острова: иначе капсула ехала бы
                // вбок вместе с ним, пока он меняет размер.
                .frame(maxWidth: .infinity)
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        let base: Glass = theme.palette.glassStyle == .clear ? .clear : .regular
        guard let tint = theme.palette.glassTint else { return base }
        return base.tint(tint.color)
    }

    /// Точки нужны там, где есть что листать. Над пустым островом они висели
    /// подсказкой к тому, чего не видно.
    var showsDots: Bool {
        guard pageCount > 1, phase != .closed else { return false }
        return hudEvent != nil || showsMedia || phase == .expanded
    }

    private var pageDots: some View {
        HStack(spacing: theme.geometry.dotSpacing) {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .fill(theme.palette.primaryText.color)
                    .opacity(index == pageIndex ? 0.9 : 0.3)
                    .frame(width: theme.geometry.dotSize, height: theme.geometry.dotSize)
            }
        }
        .animation(theme.motion.content, value: pageIndex)
    }

    /// Ширина капсулы считается по числу точек: она должна расти вместе с
    /// количеством источников, а не быть подобранной под какое-то одно.
    private var dotsCapsuleWidth: CGFloat {
        let dots = CGFloat(pageCount) * theme.geometry.dotSize
        let gaps = CGFloat(max(pageCount - 1, 0)) * theme.geometry.dotSpacing
        return dots + gaps + theme.geometry.dotsCapsulePadding * 2
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
        } else if showsMedia || (phase == .expanded && !track.isEmpty) {
            IslandMediaView(
                media: media,
                track: track,
                theme: theme,
                phase: phase,
                levels: levels,
                isDimmed: isDimmed
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
