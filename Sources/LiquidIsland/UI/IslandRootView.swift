import SwiftUI

struct IslandRootView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var media: MediaHub
    @ObservedObject var themeStore: ThemeStore = .shared
    @ObservedObject var audio: AudioLevels

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

    private var shape: IslandShape {
        IslandShape(
            style: state.shapeStyle,
            topRadius: theme.geometry.topRadius,
            bottomRadius: state.bottomRadius
        )
    }

    /// Кромка стекла: сверху блик, снизу почти ничего — так объём читается
    /// даже на чёрном.
    private var rimGradient: LinearGradient {
        LinearGradient(
            colors: [
                theme.palette.rimLight.color,
                theme.palette.rimLight.color.opacity(0.15)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var island: some View {
        ZStack {
            IslandBackground(
                shape: shape,
                theme: theme,
                glassReveal: state.phase == .expanded ? 1 : 0
            )
            .overlay(
                shape
                    .strokeBorder(rimGradient, lineWidth: theme.palette.rimWidth)
                    .opacity(state.showsMediaCard || state.phase != .closed ? 1 : 0)
            )

            content
                .frame(width: size.width, height: size.height)
                .clipped()
        }
        .frame(width: size.width, height: size.height)
        .contentShape(shape)
        // Наведение отслеживает IslandController: окно почти всё время
        // сквозное, и SwiftUI о движениях мыши просто не узнаёт.
        .onTapGesture { state.toggle() }
    }

    @ViewBuilder
    private var content: some View {
        if state.showsMediaCard || (state.phase == .expanded && state.hasMedia) {
            IslandMediaView(
                media: media,
                theme: theme,
                phase: state.phase,
                levels: audio.bands
            )
            // Свайп по тачпаду уводит карточку вбок.
            .offset(x: state.swipeOffset)
            .opacity(state.swipeFade)
        } else {
            // Без музыки остров — просто чёрное пятно, неотличимое от выреза.
            Color.clear
        }
    }
}
