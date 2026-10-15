import SwiftUI

/// Фоновый «свет состояния»: мягкие локальные свечения, окрашенные итогом месяца.
/// Изумрудное — профицит, коралловое — дефицит, фиолетовое — нейтрально. Свет несёт смысл, а не декор.
struct AmbientBackground: View {
    var tint: Color = Color.mono.violet
    var secondary: Color = Color.mono.electric
    var intensity: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.mono.background
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { timeline in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    let strength = (colorScheme == .dark ? 0.42 : 0.22) * intensity
                    let primaryCenter = CGPoint(
                        x: size.width * (0.28 + 0.05 * sin(t / 7)),
                        y: 120 + 26 * cos(t / 9)
                    )
                    let secondaryCenter = CGPoint(
                        x: size.width * (0.86 + 0.04 * cos(t / 11)),
                        y: 40 + 30 * sin(t / 13)
                    )
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .radialGradient(
                            Gradient(colors: [tint.opacity(strength), tint.opacity(0)]),
                            center: primaryCenter, startRadius: 0, endRadius: size.width * 0.85
                        )
                    )
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .radialGradient(
                            Gradient(colors: [secondary.opacity(strength * 0.7), secondary.opacity(0)]),
                            center: secondaryCenter, startRadius: 0, endRadius: size.width * 0.6
                        )
                    )
                }
            }
            // Мягкое затухание к низу экрана: свет только наверху, под балансом.
            LinearGradient(colors: [.clear, Color.mono.background.opacity(0.9), Color.mono.background],
                           startPoint: UnitPoint(x: 0.5, y: 0.25), endPoint: UnitPoint(x: 0.5, y: 0.75))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// «Спектр ликвидности»: доли счетов в общем балансе тонкой многоцветной полосой.
struct LiquidityBar: View {
    struct Segment: Identifiable, Equatable {
        let id: UUID
        let color: Color
        let value: Double
    }

    let segments: [Segment]
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let positive = segments.filter { $0.value > 0 }
            let total = positive.reduce(0) { $0 + $1.value }
            let spacing: CGFloat = 3
            let available = max(0, proxy.size.width - spacing * CGFloat(max(positive.count - 1, 0)))
            HStack(spacing: spacing) {
                if total > 0 {
                    ForEach(positive) { segment in
                        Capsule(style: .continuous)
                            .fill(LinearGradient(colors: [segment.color.opacity(0.85), segment.color], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(height, available * segment.value / total))
                    }
                } else {
                    Capsule().fill(Color.mono.surface3)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Пустое состояние с орбитальной иллюстрацией.
struct EmptyStateView<Actions: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let actions: Actions

    init(symbol: String, title: LocalizedStringKey, message: LocalizedStringKey, @ViewBuilder actions: () -> Actions) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 18) {
            OrbitIllustration(symbol: symbol)
                .frame(width: 150, height: 150)
            VStack(spacing: 8) {
                Text(title)
                    .monoFont(.title)
                    .foregroundStyle(Color.mono.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .monoFont(.callout)
                    .foregroundStyle(Color.mono.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(symbol: String, title: LocalizedStringKey, message: LocalizedStringKey) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

/// Концентрические орбиты с медленно вращающимися «спутниками».
struct OrbitIllustration: View {
    let symbol: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let time: Double = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                Self.draw(in: &context, size: size, time: time)
            }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [Color.mono.electric, Color.mono.violet], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .accessibilityHidden(true)
    }

    /// Отрисовка вынесена в функцию с явными типами: так компилятор быстро проверяет выражения.
    private static func draw(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let colors: [Color] = [Color.mono.electric, Color.mono.violet, Color.mono.cyan]
        for index in 0..<3 {
            let step = CGFloat(index)
            let radius: CGFloat = size.width * (0.22 + step * 0.13)
            let ringRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: ringRect), with: .color(Color.mono.strokeStrong), lineWidth: 1)

            let speed: Double = 0.5 - Double(index) * 0.13
            let angle: Double = time * speed + Double(index) * 2.1
            let dx: CGFloat = CGFloat(cos(angle)) * radius
            let dy: CGFloat = CGFloat(sin(angle)) * radius
            let dotRect = CGRect(x: center.x + dx - 4, y: center.y + dy - 4, width: 8, height: 8)
            let dot = Path(ellipseIn: dotRect)
            let color = colors[index]
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 4))
                layer.fill(dot, with: .color(color))
            }
            context.fill(dot, with: .color(color))
        }
    }
}

/// Скелет загрузки с бегущим бликом (без анимации при Reduce Motion).
struct ShimmerBlock: View {
    var height: CGFloat = 16
    var radius: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.mono.surface2)
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(colors: [.clear, Color.white.opacity(0.08), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.6)
                        .offset(x: phase * proxy.size.width)
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .frame(height: height)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1.4 }
            }
            .accessibilityHidden(true)
    }
}
