import SwiftUI

/// Появление и уход с размытием.
///
/// В SwiftUI такого перехода нет из коробки, но он собирается из модификатора:
/// вью въезжает уже сфокусированной, а уходит, расплываясь. Именно так меняются
/// элементы в системных интерфейсах, и от этого движение читается мягче.
struct BlurFade: ViewModifier {
    var radius: CGFloat
    var opacity: Double
    var scale: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: radius)
            .opacity(opacity)
            .scaleEffect(scale)
    }
}

extension AnyTransition {
    static func blurFade(radius: CGFloat = 8, scale: CGFloat = 0.96) -> AnyTransition {
        .modifier(
            active: BlurFade(radius: radius, opacity: 0, scale: scale),
            identity: BlurFade(radius: 0, opacity: 1, scale: 1)
        )
    }
}

extension View {
    /// Текст, который меняется размыто, а не скачком. Для цифр времени
    /// используется отдельный переход: цифры перекатываются на месте.
    func softChange<Value: Equatable>(_ value: Value, animation: Animation) -> some View {
        transaction { $0.animation = animation }
            .animation(animation, value: value)
    }
}
