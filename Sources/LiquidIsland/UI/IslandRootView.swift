import SwiftUI

struct IslandRootView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var media: MediaHub
    @ObservedObject var themeStore: ThemeStore = .shared
    @ObservedObject var audio: AudioLevels
    @ObservedObject var hud: SystemHUD
    /// Вызывается на каждом кадре анимации с текущим размером острова.
    var onSizeChange: @Sendable (CGSize) -> Void = { _ in }

    private var theme: IslandTheme { themeStore.theme }
    private var size: CGSize { state.size }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // По умолчанию ноль: остров врастает в кромку экрана, а не висит под ней.
        .padding(.top, theme.geometry.floatingTopInset)
    }

    private var island: some View {
        IslandBody(
            media: media,
            theme: theme,
            phase: state.phase,
            size: size,
            shapeStyle: state.shapeStyle,
            showsMedia: state.showsMediaCard,
            levels: audio.bands,
            hudEvent: state.hudEvent,
            swipeOffset: state.swipeOffset,
            swipeFade: state.swipeFade
        )
        // Слой стекла живёт в AppKit и берёт размер отсюда: Shape сообщает
        // его на каждом кадре пружины, поэтому стекло идёт с островом в ногу.
        .reportingAnimatedSize(size, to: onSizeChange)
        .shadow(
            color: .black.opacity(state.phase == .expanded ? 0.4 : 0),
            radius: 18, x: 0, y: 8
        )
        .contentShape(
            IslandShape(
                style: state.shapeStyle,
                topRadius: theme.geometry.topRadius,
                bottomRadius: state.bottomRadius
            )
        )
        // Наведение отслеживает IslandController: окно почти всё время
        // сквозное, и SwiftUI о движениях мыши просто не узнаёт.
        .scaleEffect(state.pressScale)
        .onTapGesture { state.tap() }
    }
}
