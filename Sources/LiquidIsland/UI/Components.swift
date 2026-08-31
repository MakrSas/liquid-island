import SwiftUI

// MARK: - Обложка

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [Color(white: 0.28), Color(white: 0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}

// MARK: - Визуализатор

/// Тот самый «эквалайзер» справа в компактном виде.
/// Это не анализ звука, а честная имитация — системного доступа к сэмплам
/// у нас нет, а картинка должна жить.
struct WaveformView: View {
    var isPlaying: Bool
    var color: Color
    /// Реальные уровни по полосам. Пусто — рисуем ровное дыхание по таймеру:
    /// без разрешения на запись звука взять настоящие неоткуда.
    var levels: [Float] = []
    var barCount: Int = 4
    var barWidth: CGFloat = 2.5
    var height: CGFloat = 14

    var body: some View {
        Group {
            if levels.isEmpty {
                synthetic
            } else {
                HStack(alignment: .center, spacing: barWidth * 0.8) {
                    ForEach(Array(levels.prefix(barCount).enumerated()), id: \.offset) { _, level in
                        Capsule(style: .continuous)
                            .fill(color)
                            .frame(width: barWidth, height: height * (0.18 + 0.82 * CGFloat(level)))
                    }
                }
                .frame(height: height, alignment: .center)
                // Своей анимации у полосок нет намеренно. Уровни и так
                // приходят тридцать раз в секунду, а отдельная кривая поверх
                // пружины морфинга разводит полоски по разным таймингам —
                // часть отстаёт, и это видно при раскрытии.
                .animation(nil, value: levels)
            }
        }
    }

    private var synthetic: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: barWidth * 0.8) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: barWidth, height: barHeight(index: index, time: t))
                }
            }
            .frame(height: height, alignment: .center)
        }
    }

    private func barHeight(index: Int, time: Double) -> CGFloat {
        guard isPlaying else { return height * 0.22 }
        // Разные частоты и сдвиги дают неповторяющийся, «живой» рисунок.
        let speed = 3.2 + Double(index) * 0.7
        let offset = Double(index) * 1.3
        let wave = (sin(time * speed + offset) + 1) / 2          // 0…1
        let flutter = (sin(time * speed * 2.7 + offset * 2) + 1) / 2
        let value = wave * 0.7 + flutter * 0.3
        return height * (0.25 + 0.75 * value)
    }
}

// MARK: - Прогресс

struct ProgressBarView: View {
    var progress: Double
    var trackColor: Color
    var fillColor: Color
    var thickness: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor)
                Capsule()
                    .fill(fillColor)
                    .frame(width: max(geo.size.width * progress, progress > 0 ? thickness : 0))
            }
        }
        .frame(height: thickness)
    }
}

// MARK: - Бегущая строка

/// Длинные названия треков не обрезаются, а плавно проезжают — как в iOS.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    var speed: Double = 30      // точек в секунду
    var gap: CGFloat = 36
    var pause: Double = 1.4

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    private var needsScroll: Bool { textWidth > containerWidth + 1 }

    var body: some View {
        GeometryReader { geo in
            Group {
                if needsScroll {
                    TimelineView(.animation) { context in
                        let cycle = Double(textWidth + gap) / speed + pause
                        let t = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: cycle)
                        let travel = max(t - pause, 0) * speed
                        HStack(spacing: gap) {
                            label
                            label
                        }
                        .offset(x: -CGFloat(travel))
                    }
                } else {
                    label
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .onAppear { containerWidth = geo.size.width }
            .onChange(of: geo.size.width) { _, new in containerWidth = new }
        }
        .frame(height: measuredHeight)
        .clipped()
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { textWidth = proxy.size.width }
                        .onChange(of: text) { _, _ in textWidth = proxy.size.width }
                }
            )
    }

    private var measuredHeight: CGFloat { 18 }
}

// MARK: - Кнопка транспорта

struct TransportButton: View {
    let systemName: String
    let size: CGFloat
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white)
                // Пауза и воспроизведение перетекают друг в друга, а не
                // подменяются: у символов есть родной переход для этого.
                .contentTransition(.symbolEffect(.replace.downUp))
                .frame(width: size * 1.9, height: size * 1.9)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.86 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.6), value: pressed)
        .onHover { _ in }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}
