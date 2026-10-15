import SwiftUI
import MonoIntelligence

/// Инсайт в стиле журнальной цитаты: тонкая линия тона, кикер, спокойный текст.
struct InsightQuoteView: View {
    let insight: Insight

    private var tint: Color {
        switch insight.tone {
        case .positive: return Color.mono.positive
        case .negative: return Color.mono.negative
        case .warning: return Color.mono.warning
        case .neutral: return Color.mono.accentText
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Capsule(style: .continuous)
                .fill(tint)
                .frame(width: 2)
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
