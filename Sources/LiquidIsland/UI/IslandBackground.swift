import SwiftUI

/// Подложка острова: чёрный верх, переходящий книзу в жидкое стекло.
///
/// Стекло — нативное (`NSGlassEffectView`), поэтому оно живёт по системным
/// правилам: следует настройкам прозрачности и контраста, реагирует на то,
/// что под ним. У него обязательно есть собственная кромка с отступом от краёв
/// острова: преломление и блик считаются именно по ней, и без неё эффект
/// вырождается в обычное размытие. Стык со чёрным размывается градиентом,
/// поэтому кромка читается только снизу и по бокам — сверху стекло втекает
/// в чёрное.
struct IslandBackground: View {
    let shape: IslandShape
    let theme: IslandTheme
    /// 0 — сплошной чёрный, 1 — переход в стекло раскрыт полностью.
    let glassReveal: Double

    var body: some View {
        GeometryReader { geo in
            ZStack {
                shape.fill(theme.palette.background.color)

                if theme.palette.useLiquidGlass && glassReveal > 0 {
                    glass(in: geo.size)
                        .opacity(glassReveal)
                }
            }
        }
        .clipShape(shape)
    }

    private func glass(in size: CGSize) -> some View {
        let inset = theme.geometry.glassInset
        let height = size.height * theme.geometry.glassHeightFraction

        return LiquidGlassView(
            cornerRadius: theme.geometry.glassCornerRadius,
            isClear: theme.palette.glassStyle == .clear,
            tint: theme.palette.glassTint?.nsColor,
            isInteractive: theme.palette.glassInteractive
        )
        .frame(width: size.width - inset * 2, height: height)
        // Верхний край стекла растворяем — там оно должно втекать в чёрное,
        // а не резать остров пополам.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: theme.geometry.glassFadeEnd - theme.geometry.glassFadeStart),
                    .init(color: .white, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(width: size.width, height: size.height, alignment: .bottom)
        .padding(.bottom, inset)
    }
}
