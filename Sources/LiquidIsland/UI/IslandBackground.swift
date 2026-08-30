import SwiftUI

/// Подложка острова.
///
/// Само стекло сюда не входит — оно лежит отдельным слоем под SwiftUI и живёт
/// в AppKit, потому что backdrop-эффект не подчиняется обрезке SwiftUI.
/// Здесь только чёрный: сплошной в покое и растворяющийся книзу в раскрытом
/// виде, чтобы стекло под ним проступило.
struct IslandBackground: View {
    let shape: IslandShape
    let theme: IslandTheme
    /// 0 — сплошной чёрный, 1 — низ раскрыт и стекло видно.
    let glassReveal: Double

    var body: some View {
        Group {
            if theme.palette.useLiquidGlass && glassReveal > 0.5 {
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
            } else {
                shape.fill(theme.palette.background.color)
            }
        }
        .allowsHitTesting(false)
    }
}
