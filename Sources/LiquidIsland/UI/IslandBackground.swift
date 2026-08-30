import SwiftUI

/// Подложка острова: чёрный верх, плавно переходящий в жидкое стекло книзу.
///
/// Стекло — нативное (`NSGlassEffectView`), поэтому оно живёт по системным
/// правилам: следует настройкам прозрачности и контраста, реагирует на то,
/// что под ним. Чёрный слой лежит поверх и растворяется к низу, открывая его.
/// В покое остров непрозрачно чёрный — переход появляется только в раскрытом виде.
struct IslandBackground: View {
    let shape: IslandShape
    let theme: IslandTheme
    /// 0 — сплошной чёрный, 1 — переход в стекло раскрыт полностью.
    let glassReveal: Double

    var body: some View {
        ZStack {
            if theme.palette.useLiquidGlass && glassReveal > 0 {
                LiquidGlassView(
                    cornerRadius: theme.geometry.bottomRadiusOpen,
                    isClear: theme.palette.glassStyle == .clear,
                    tint: theme.palette.glassTint?.nsColor,
                    isInteractive: theme.palette.glassInteractive
                )
                .opacity(glassReveal)
            }

            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: theme.palette.background.color, location: 0),
                        .init(
                            color: theme.palette.background.color,
                            location: fadeStart
                        ),
                        .init(
                            color: theme.palette.background.color.opacity(1 - glassReveal),
                            location: fadeEnd
                        )
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .clipShape(shape)
    }

    /// Пока стекло не раскрыто, точка перехода уезжает за нижнюю кромку —
    /// так чёрный остаётся сплошным, а не подтаивает раньше времени.
    private var fadeStart: Double {
        1 - (1 - theme.geometry.glassFadeStart) * glassReveal
    }

    private var fadeEnd: Double {
        max(fadeStart, theme.geometry.glassFadeEnd)
    }
}
