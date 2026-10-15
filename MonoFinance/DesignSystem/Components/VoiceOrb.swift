import SwiftUI

/// Голосовой «прибор»: акцентное ядро и радиальная шкала из тонких штрихов.
/// Во время записи штрихи показывают историю громкости по кругу, ядро чуть «дышит» в такт речи.
/// В покое — неподвижная шкала, как циферблат. Без свечений и радуги.
struct VoiceOrb: View {
    /// Громкость 0…1.
    var level: Double
    var isActive: Bool
    /// История громкости (последние значения) для радиальной шкалы.
    var levels: [Double] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isActive || reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                Self.draw(in: &context, size: size, time: t, level: level, levels: levels, active: isActive, animate: !reduceMotion)
            }
        }
        .accessibilityHidden(true)
    }

    private static func draw(in context: inout GraphicsContext, size: CGSize, time: Double, level: Double,
                             levels: [Double], active: Bool, animate: Bool) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let side = min(size.width, size.height)
        let base: CGFloat = side * 0.24
        let accent = Color.mono.accent
        let tick = Color.mono.accentText

        // Радиальная шкала.
        let count = 72
        let inner: CGFloat = base * 1.42
        let maxLength: CGFloat = side * 0.5 - inner - 4
        for index in 0..<count {
            let angle = Double(index) / Double(count) * 2 * .pi - .pi / 2
            var value: Double = 0
            if active {
                if !levels.isEmpty {
                    // Симметричное отображение истории: свежие значения сверху, старые расходятся вниз.
                    let mirrored = index <= count / 2 ? index : count - index
                    let position = levels.count - 1 - Int(Double(mirrored) / Double(count / 2) * Double(min(levels.count - 1, 40)))
                    value = levels[max(0, min(levels.count - 1, position))]
                }
                if animate {
                    value += 0.06 * (1 + sin(time * 3 + Double(index) * 0.5)) * (0.4 + level)
                }
            }
            let length: CGFloat = 3 + CGFloat(min(value, 1)) * maxLength
            let start = CGPoint(x: center.x + CGFloat(cos(angle)) * inner, y: center.y + CGFloat(sin(angle)) * inner)
            let end = CGPoint(x: center.x + CGFloat(cos(angle)) * (inner + length), y: center.y + CGFloat(sin(angle)) * (inner + length))
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            let opacity = active ? 0.35 + 0.65 * min(value * 1.4, 1) : (index % 6 == 0 ? 0.45 : 0.18)
            context.stroke(path, with: .color(tick.opacity(opacity)), style: StrokeStyle(lineWidth: index % 6 == 0 ? 2 : 1.4, lineCap: .round))
        }

        // Кольцо-орбита.
        let ringRadius = base * (1.18 + (active ? CGFloat(level) * 0.08 : 0))
        let ring = Path(ellipseIn: CGRect(x: center.x - ringRadius, y: center.y - ringRadius, width: ringRadius * 2, height: ringRadius * 2))
        context.stroke(ring, with: .color(accent.opacity(active ? 0.55 : 0.3)), lineWidth: 1)

        // Ядро.
        let breathing: CGFloat = active && animate ? CGFloat(level) * 0.07 + 0.015 * CGFloat(sin(time * 2.4)) : 0
        let coreRadius = base * (1 + breathing)
        let core = Path(ellipseIn: CGRect(x: center.x - coreRadius, y: center.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2))
        context.fill(core, with: .color(accent))
        context.fill(core, with: .linearGradient(
            Gradient(colors: [Color.white.opacity(0.16), Color.clear]),
            startPoint: CGPoint(x: center.x, y: center.y - coreRadius),
            endPoint: CGPoint(x: center.x, y: center.y + coreRadius)
        ))
    }
}

/// Волна громкости — история уровней последних секунд.
struct WaveformView: View {
    let levels: [Double]
    var tint: Color = Color.mono.accentText

    var body: some View {
        Canvas { context, size in
            guard !levels.isEmpty else { return }
            let barWidth: CGFloat = 2.5
            let gap: CGFloat = 3
            let count = Int(size.width / (barWidth + gap))
            let visible = levels.suffix(count)
            for (index, level) in visible.enumerated() {
                let height = max(2.5, CGFloat(level) * size.height)
                let x = size.width - CGFloat(visible.count - index) * (barWidth + gap)
                let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.25), with: .color(tint.opacity(0.3 + 0.7 * level)))
            }
        }
        .accessibilityHidden(true)
    }
}
