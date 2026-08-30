import SwiftUI

/// Подложка острова: чёрный верх, переходящий книзу в стекло.
///
/// Стекло занимает всю фигуру — никаких отступов, иначе по краям остаются
/// чёрные рамки. Переход рисуется чёрным градиентом поверх: `mask` и `opacity`
/// применять к стеклу нельзя, они заставляют SwiftUI отрисовать его в отдельный
/// слой, и живая подложка теряется.
struct IslandBackground: View {
    let shape: IslandShape
    let theme: IslandTheme
    /// 0 — сплошной чёрный, 1 — переход в стекло раскрыт полностью.
    let glassReveal: Double

    private var showsGlass: Bool {
        theme.palette.useLiquidGlass && glassReveal > 0.5
    }

    var body: some View {
        ZStack {
            if showsGlass {
                LiquidGlassView(
                    cornerRadius: theme.geometry.bottomRadiusOpen,
                    isClear: theme.palette.glassStyle == .clear,
                    tint: theme.palette.glassTint?.nsColor,
                    isInteractive: theme.palette.glassInteractive
                )

                // Чёрный сверху вниз растворяется, открывая стекло к низу.
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: theme.palette.background.color, location: 0),
                            .init(
                                color: theme.palette.background.color,
                                location: theme.geometry.glassFadeStart
                            ),
                            .init(color: .clear, location: theme.geometry.glassFadeEnd)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)
            } else {
                shape.fill(theme.palette.background.color)
            }
        }
        .clipShape(shape)
        // Стекло должно исчезать вместе с островом, а не растворяться следом:
        // анимированное снятие оставляет висеть подложку на добрую секунду.
        .transaction { $0.animation = nil }
    }
}
