import SwiftUI

/// Подложка острова.
///
/// Само стекло сюда не входит — оно лежит отдельным слоем под SwiftUI и живёт
/// в AppKit, потому что backdrop-эффект не подчиняется обрезке SwiftUI.
///
/// Слоя два, и оба существуют всегда. Нижний — чёрный, растворяющийся книзу:
/// сквозь него проступает стекло. Верхний — сплошной чёрный, который в покое
/// закрывает первый целиком и тает при раскрытии. Ветвления между двумя
/// разными фонами здесь быть не должно: SwiftUI считает их разными вьюхами и
/// делает перекрёстное затухание вместо перетекания.
struct IslandBackground: View {
    let shape: IslandShape
    let theme: IslandTheme
    /// 0 — сплошной чёрный, 1 — низ раскрыт и стекло видно.
    let glassReveal: Double

    var body: some View {
        ZStack {
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

            shape
                .fill(theme.palette.background.color)
                .opacity(theme.palette.useLiquidGlass ? 1 - glassReveal : 1)
        }
        .allowsHitTesting(false)
    }
}
