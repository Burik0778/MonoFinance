import SwiftUI

/// Фон экрана: глубокий графит с едва заметным светом сверху. Статичный — ничего не анимирует и не расходует батарею.
/// `haze` добавляет холодную акцентную дымку под шапкой (только для главных экранов, очень слабо).
struct MonoBackdrop: View {
    var haze = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            Color.mono.background
            LinearGradient(
                colors: [Color.white.opacity(colorScheme == .dark ? 0.035 : 0.5), .clear],
                startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45)
            )
            if haze {
                RadialGradient(
                    colors: [Color.mono.accent.opacity(colorScheme == .dark ? 0.14 : 0.08), .clear],
                    center: UnitPoint(x: 0.15, y: 0), startRadius: 0, endRadius: 420
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Доли в тонкой сегментированной полосе (счета в балансе, категории в расходах).
struct LiquidityBar: View {
    struct Segment: Identifiable, Equatable {
        let id: UUID
        let color: Color
        let value: Double
    }

    let segments: [Segment]
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let positive = segments.filter { $0.value > 0 }
            let total = positive.reduce(0) { $0 + $1.value }
            let spacing: CGFloat = 2
            let available = max(0, proxy.size.width - spacing * CGFloat(max(positive.count - 1, 0)))
            HStack(spacing: spacing) {
                if total > 0 {
                    ForEach(positive) { segment in
                        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                            .fill(segment.color)
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

/// Пустое состояние: знак в концентрических волосяных кольцах, заголовок, пояснение, действие.
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
        VStack(spacing: 16) {
            OrbitIllustration(symbol: symbol)
                .frame(width: 112, height: 112)
            VStack(spacing: 6) {
                Text(title)
                    .monoFont(.title2)
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
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(symbol: String, title: LocalizedStringKey, message: LocalizedStringKey) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

/// Знак в концентрических кольцах. Внешнее кольцо медленно «дышит» один раз при появлении.
struct OrbitIllustration: View {
    let symbol: String
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .strokeBorder(Color.mono.strokeStrong.opacity(1 - Double(index) * 0.3), lineWidth: 1)
                        .frame(width: side * (0.5 + CGFloat(index) * 0.25), height: side * (0.5 + CGFloat(index) * 0.25))
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.85)
                        .opacity(appeared || reduceMotion ? 1 : 0)
                        .animation(Motion.animation(.gentle, reduceMotion: reduceMotion).delay(Double(index) * 0.06), value: appeared)
                }
                Circle()
                    .fill(Color.mono.surface2)
                    .frame(width: side * 0.5, height: side * 0.5)
                Image(systemName: symbol)
                    .font(.system(size: side * 0.2, weight: .medium))
                    .foregroundStyle(Color.mono.accentText)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear { appeared = true }
        .accessibilityHidden(true)
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
                    LinearGradient(colors: [.clear, Color.white.opacity(0.06), .clear], startPoint: .leading, endPoint: .trailing)
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
