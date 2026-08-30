import SwiftUI

/// Подложка острова: либо плотная заливка, либо стекло.
///
/// Стекло — это настоящее размытие того, что под окном (`NSVisualEffectView`),
/// притемнённое до нужной плотности, плюс мягкий блик сверху. На чёрном фоне
/// эффект тонкий, поэтому он и работает: остров остаётся островом, но перестаёт
/// быть плоской дырой.
struct IslandBackground: View {
    let shape: IslandShape
    let theme: IslandTheme

    var body: some View {
        ZStack {
            if theme.palette.useGlass {
                VisualEffectView(
                    material: theme.palette.glassMaterial.nsMaterial,
                    blendingMode: .behindWindow
                )
                shape.fill(theme.palette.background.color.opacity(theme.palette.glassTint))
                // Блик по верхней кромке — то, что делает поверхность стеклом,
                // а не просто полупрозрачным пятном.
                shape.fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(theme.palette.glassSheen),
                            .white.opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            } else {
                shape.fill(theme.palette.background.color)
            }
        }
        .clipShape(shape)
    }
}

/// Мост к `NSVisualEffectView` — размытию, которого в SwiftUI на macOS нет.
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}
