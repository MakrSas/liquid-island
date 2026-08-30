import SwiftUI

/// Подложка острова: чёрный верх, переходящий книзу в жидкое стекло.
///
/// Важная тонкость: к самому стеклу нельзя применять `mask` или `opacity`.
/// Оба заставляют SwiftUI отрисовать вью в отдельный слой, и нативное стекло
/// теряет живую подложку — остаётся плоское размытие. Поэтому переход
/// рисуется чёрным градиентом поверх стекла, а не маской по нему.
struct IslandBackground: View {
    let shape: IslandShape
    let theme: IslandTheme
    /// 0 — сплошной чёрный, 1 — переход в стекло раскрыт полностью.
    let glassReveal: Double

    private var showsGlass: Bool {
        theme.palette.useLiquidGlass && glassReveal > 0.5
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                shape.fill(theme.palette.background.color)

                if showsGlass {
                    LiquidGlassView(
                        cornerRadius: theme.geometry.glassCornerRadius,
                        isClear: theme.palette.glassStyle == .clear,
                        tint: theme.palette.glassTint?.nsColor,
                        isInteractive: theme.palette.glassInteractive
                    )
                    .frame(
                        width: geo.size.width - theme.geometry.glassInset * 2,
                        height: geo.size.height * theme.geometry.glassHeightFraction
                    )
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                    .padding(.bottom, theme.geometry.glassInset)

                    // Чёрный сверху вниз растворяется — он и прячет верхнюю
                    // кромку стекла, оставляя видимыми боковые и нижнюю.
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
                }
            }
        }
        .clipShape(shape)
    }
}
