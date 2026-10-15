import SwiftUI

/// «Голосовая сфера»: три световых лепестка, дышащих в ритм громкости речи.
struct VoiceOrb: View {
    /// Громкость 0…1.
    var level: Double
    var isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isActive || reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let base = min(size.width, size.height) * 0.30
                let energy = isActive ? (0.35 + level * 0.9) : 0.15
                let colors: [Color] = [Color.mono.electric, Color.mono.violet, Color.mono.cyan]
                for (index, color) in colors.enumerated() {
                    var path = Path()
                    let steps = 72
                    for step in 0...steps {
                        let angle = Double(step) / Double(steps) * 2 * .pi
                        let phase = reduceMotion ? 0 : t * (0.9 + Double(index) * 0.35)
                        let wobble = sin(angle * 3 + phase + Double(index)) * 0.07 + sin(angle * 5 - phase * 0.8) * 0.04
                        let radius = base * (1 + wobble * energy + level * 0.18)
                        let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    path.closeSubpath()
                    context.drawLayer { layer in
                        layer.addFilter(.blur(radius: 16))
                        layer.blendMode = .plusLighter
                        layer.fill(path, with: .color(color.opacity(0.75)))
                    }
                }
                let core = Path(ellipseIn: CGRect(x: center.x - base * 0.62, y: center.y - base * 0.62, width: base * 1.24, height: base * 1.24))
                context.fill(core, with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.85), Color.mono.violet.opacity(0.0)]),
                    center: center, startRadius: 0, endRadius: base * 0.62
                ))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Волна громкости — история уровней последних секунд.
struct WaveformView: View {
    let levels: [Double]
    var tint: Color = Color.mono.violet

    var body: some View {
        Canvas { context, size in
            guard !levels.isEmpty else { return }
            let barWidth: CGFloat = 3
            let gap: CGFloat = 3
            let count = Int(size.width / (barWidth + gap))
            let visible = levels.suffix(count)
            for (index, level) in visible.enumerated() {
                let height = max(3, CGFloat(level) * size.height)
                let x = size.width - CGFloat(visible.count - index) * (barWidth + gap)
                let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(tint.opacity(0.35 + 0.65 * level)))
            }
        }
        .accessibilityHidden(true)
    }
}
