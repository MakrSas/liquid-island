import SwiftUI

/// Мягкое появление и уход.
///
/// Размытия здесь намеренно нет. `blur` заставляет SwiftUI отрисовать вью в
/// отдельный растровый слой, и в прозрачном окне освободившиеся пиксели никто
/// не перерисовывает — размытый снимок остаётся висеть на экране поверх обоев
/// уже после того, как остров свернулся. Масштаб и прозрачность дают ту же
/// мягкость без этой платы.
struct SoftFade: ViewModifier {
    var opacity: Double
    var scale: CGFloat
    var offsetY: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale)
            .offset(y: offsetY)
    }
}

extension AnyTransition {
    static func softFade(scale: CGFloat = 0.94, offsetY: CGFloat = -4) -> AnyTransition {
        .modifier(
            active: SoftFade(opacity: 0, scale: scale, offsetY: offsetY),
            identity: SoftFade(opacity: 1, scale: 1, offsetY: 0)
        )
    }
}
