import SwiftUI

/// График пружины: как значение идёт от нуля к единице во времени.
///
/// Рисуем по той же формуле, по которой считает SwiftUI, поэтому кривая
/// показывает настоящее движение, а не приблизительную картинку. Ползунки
/// демпфирования и отклика видно сразу: перелёт за единицу — это отскок.
struct SpringCurve: View {
    let response: Double
    let damping: Double

    /// Сколько времени показываем — с запасом относительно отклика.
    private var duration: Double { max(response * 3.5, 0.6) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack {
                    // Единица — цель движения. Всё, что выше, это перелёт.
                    Path { path in
                        let y = geo.size.height * 0.25
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.secondary.opacity(0.4))

                    Path { path in
                        let steps = 120
                        for step in 0...steps {
                            let t = duration * Double(step) / Double(steps)
                            let value = position(at: t)
                            let point = CGPoint(
                                x: geo.size.width * Double(step) / Double(steps),
                                // 0 внизу, 1 на четверти сверху — остаётся
                                // место, чтобы увидеть перелёт.
                                y: geo.size.height * (1 - value * 0.75)
                            )
                            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                        }
                    }
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                }
            }
            .frame(height: 74)
            .padding(.vertical, 4)

            HStack {
                Text("0")
                Spacer()
                Text(String(format: "%.2f с", duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    /// Положение пружины в момент `t`, от 0 к 1.
    ///
    /// SwiftUI задаёт пружину через отклик и долю демпфирования: отклик —
    /// период собственных колебаний, доля — насколько они гасятся. При доле
    /// меньше единицы система колеблется и перелетает цель, при единице
    /// приходит к ней без отскока.
    private func position(at t: Double) -> Double {
        let omega = 2 * Double.pi / max(response, 0.0001)
        let zeta = min(max(damping, 0.0001), 1)

        if zeta < 1 {
            let damped = omega * (1 - zeta * zeta).squareRoot()
            let decay = exp(-zeta * omega * t)
            return 1 - decay * (cos(damped * t) + (zeta * omega / damped) * sin(damped * t))
        }
        // Критическое демпфирование: колебаний нет вовсе.
        let decay = exp(-omega * t)
        return 1 - decay * (1 + omega * t)
    }
}
