import SwiftUI
import MonoIntelligence

/// Инсайт в стиле журнальной цитаты: цветная линия, кикер, текст серифом.
struct InsightQuoteView: View {
    let insight: Insight

    private var tint: Color {
        switch insight.tone {
        case .positive: return Color.mono.emerald
        case .negative: return Color.mono.coral
        case .warning: return Color.mono.tangerine
        case .neutral: return Color.mono.cyan
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Capsule(style: .continuous)
                .fill(LinearGradient(colors: [tint, tint.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: insight.title)
                    .monoFont(.kicker)
                    .foregroundStyle(tint)
                Text(verbatim: insight.text)
                    .monoFont(.quote)
                    .foregroundStyle(Color.mono.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .monoSurface(padding: 18)
        .accessibilityElement(children: .combine)
    }
}
