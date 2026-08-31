import SwiftUI

/// Плашка системного события: значок, шкала и значение.
///
/// Сознательно повторяет пропорции карточки трека — остров не должен
/// перестраиваться, когда одно сменяет другое.
struct HUDView: View {
    let event: SystemEvent
    let theme: IslandTheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: event.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.palette.primaryText.color)
                .frame(width: 20)
                .contentTransition(.symbolEffect(.replace))

            ProgressBarView(
                progress: Double(event.level),
                trackColor: theme.palette.progressTrack.color,
                fillColor: theme.palette.progressFill.color,
                thickness: 4
            )

            Text(event.readout)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(theme.palette.primaryText.color)
                // Ширина фиксированная, а не минимальная: иначе на переходе
                // от 9 к 100 значение раздвигает шкалу и всё едет вбок.
                .frame(width: 34, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .animation(theme.motion.content, value: event)
    }
}
