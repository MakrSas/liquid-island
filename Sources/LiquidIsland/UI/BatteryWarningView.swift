import SwiftUI

/// Предупреждение о низком заряде: две строки и кнопка справа.
///
/// Включить режим энергосбережения из приложения нельзя — `pmset` требует
/// прав администратора, а публичного API у режима нет. Поэтому кнопка ведёт
/// в раздел «Аккумулятор» системных настроек, где переключатель под рукой.
/// Обещать больше, чем можем, тут неуместно, поэтому и подпись честная.
struct BatteryWarningView: View {
    let charge: Int
    let theme: IslandTheme

    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(charge)% заряда")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.palette.primaryText.color)
                Text("Открыть настройки экономии")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.palette.secondaryText.color)
            }

            Spacer(minLength: 8)

            Button {
                openBatterySettings()
            } label: {
                batteryGlyph
            }
            .buttonStyle(.plain)
        }
        .onAppear { pulsing = true }
    }

    /// Значок батареи с пульсирующим ореолом — он и подсказывает, что сюда
    /// можно нажать.
    private var batteryGlyph: some View {
        ZStack {
            Capsule()
                .fill(Color.red.opacity(0.22))
                .frame(width: 74, height: 44)

            Circle()
                .strokeBorder(Color.red.opacity(0.55), lineWidth: 2)
                .frame(width: 34, height: 34)
                .scaleEffect(pulsing ? 1.18 : 0.9)
                .opacity(pulsing ? 0 : 0.9)
                .animation(
                    .easeOut(duration: 1.4).repeatForever(autoreverses: false),
                    value: pulsing
                )

            Image(systemName: "battery.25")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.red)
        }
        .contentShape(Capsule())
    }

    private func openBatterySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery")
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
