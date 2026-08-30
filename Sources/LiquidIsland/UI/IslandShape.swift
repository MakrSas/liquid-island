import SwiftUI

/// Форма острова.
///
/// В режиме `.notch` верхние углы «вывернуты» наружу — они втекают в кромку
/// экрана ровно так же, как это делает аппаратный вырез.
/// В режиме `.floating` (маки без чёлки) это обычная скруглённая пилюля,
/// повторяющая Dynamic Island на iPhone.
struct IslandShape: InsettableShape {
    enum Style { case notch, floating }

    var style: Style
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    /// Сдвиг внутрь для обводки — заполняет требование InsettableShape.
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> IslandShape {
        var copy = self
        copy.inset += amount
        return copy
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in outerRect: CGRect) -> Path {
        let rect = outerRect.insetBy(dx: inset, dy: inset)
        switch style {
        case .floating:
            let r = min(bottomRadius, min(rect.width, rect.height) / 2)
            return Path(roundedRect: rect, cornerRadius: r, style: .continuous)
        case .notch:
            return notchPath(in: rect)
        }
    }

    private func notchPath(in rect: CGRect) -> Path {
        var p = Path()
        let top = min(topRadius, rect.width / 2)
        let bottom = min(bottomRadius, min(rect.width / 2, rect.height))

        // Слева от выреза: подходим к кромке экрана и заворачиваем внутрь.
        p.move(to: CGPoint(x: rect.minX - top, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + top),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        // Левая стенка вниз.
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bottom))
        // Нижний левый угол.
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        // Низ.
        p.addLine(to: CGPoint(x: rect.maxX - bottom, y: rect.maxY))
        // Нижний правый угол.
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        // Правая стенка вверх.
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + top))
        // Выворот вправо к кромке экрана.
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX + top, y: rect.minY),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        p.closeSubpath()
        return p
    }
}
