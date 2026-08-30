import SwiftUI

/// Сообщает наружу размер острова на каждом кадре анимации.
///
/// `GeometryReader` с `onChange` для этого не годится: он отдаёт значение по
/// итогам изменения, а не промежуточные кадры пружины — стекло из-за этого
/// прыгало сразу в конечный размер, обгоняя сам остров.
///
/// `Animatable` решает это по-другому: SwiftUI сам присваивает
/// `animatableData` на каждом шаге интерполяции, и мы читаем ровно то
/// значение, которое сейчас на экране.
struct AnimatedSizeReporter: ViewModifier, @preconcurrency Animatable {
    var size: CGSize
    var report: (CGSize) -> Void

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(size.width, size.height) }
        set { size = CGSize(width: newValue.first, height: newValue.second) }
    }

    func body(content: Content) -> some View {
        // Побочный эффект в теле оправдан: наружу уходит только значение для
        // слоя AppKit, состояние SwiftUI это не меняет и цикла не создаёт.
        report(size)
        return content
    }
}

extension View {
    func reportingAnimatedSize(_ size: CGSize, to report: @escaping (CGSize) -> Void) -> some View {
        modifier(AnimatedSizeReporter(size: size, report: report))
    }
}
