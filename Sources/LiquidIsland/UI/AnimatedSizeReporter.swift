import SwiftUI
import Foundation

/// Сообщает наружу размер острова на каждом кадре анимации.
///
/// Здесь намеренно `Shape`, а не `ViewModifier`. У модификатора тело SwiftUI
/// может не вызывать вовсе, если тот возвращает содержимое без изменений, —
/// проверено, вызовов не было ни одного. А `path(in:)` у фигуры вызывается на
/// каждом кадре: на этом построена вся анимация фигур в SwiftUI, и другого
/// способа увидеть промежуточные значения пружины у нас нет.
///
/// `GeometryReader` с `onChange` тоже не подходит: он отдаёт итог изменения,
/// а не кадры интерполяции, и стекло прыгало в конечный размер, обгоняя
/// остров.
struct AnimatedSizeProbe: Shape {
    var size: CGSize
    var report: @Sendable (CGSize) -> Void

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(size.width, size.height) }
        set { size = CGSize(width: newValue.first, height: newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        let value = size
        if Thread.isMainThread {
            report(value)
        } else {
            let handler = report
            DispatchQueue.main.async { handler(value) }
        }
        return Path()
    }
}

extension View {
    func reportingAnimatedSize(
        _ size: CGSize,
        to report: @escaping @Sendable (CGSize) -> Void
    ) -> some View {
        background(
            AnimatedSizeProbe(size: size, report: report)
                .fill(Color.clear)
                .allowsHitTesting(false)
        )
    }
}
