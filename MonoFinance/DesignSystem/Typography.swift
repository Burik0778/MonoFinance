import SwiftUI

/// Токен шрифта: размер масштабируется Dynamic Type относительно `relativeTo`.
struct FontToken: Sendable {
    enum Style: Sendable {
        case `default`
        case serif
        case rounded
        case monospaced
        /// SF Pro Expanded — надписи-«кикеры».
        case expanded
    }

    let size: CGFloat
    let weight: Font.Weight
    let style: Style
    let relativeTo: Font.TextStyle
    let tracking: CGFloat

    static let hero = MonoTokens.Typography.hero
    static let display = MonoTokens.Typography.display
    static let title = MonoTokens.Typography.title
    static let title2 = MonoTokens.Typography.title2
    static let quote = MonoTokens.Typography.quote
    static let headline = MonoTokens.Typography.headline
    static let body = MonoTokens.Typography.body
    static let callout = MonoTokens.Typography.callout
    static let subhead = MonoTokens.Typography.subhead
    static let footnote = MonoTokens.Typography.footnote
    static let caption = MonoTokens.Typography.caption
    static let kicker = MonoTokens.Typography.kicker
    static let amount = MonoTokens.Typography.amount
    static let amountRow = MonoTokens.Typography.amountRow

    func font(size: CGFloat, monospacedDigits: Bool = false) -> Font {
        let base: Font
        switch style {
        case .default: base = .system(size: size, weight: weight, design: .default)
        case .serif: base = .system(size: size, weight: weight, design: .serif)
        case .rounded: base = .system(size: size, weight: weight, design: .rounded)
        case .monospaced: base = .system(size: size, weight: weight, design: .monospaced)
        case .expanded: base = .system(size: size, weight: weight, design: .default).width(.expanded)
        }
        return monospacedDigits ? base.monospacedDigit() : base
    }
}

/// Применяет токен шрифта с поддержкой Dynamic Type.
struct MonoFontModifier: ViewModifier {
    let token: FontToken
    let monospacedDigits: Bool
    @ScaledMetric private var size: CGFloat

    init(token: FontToken, monospacedDigits: Bool) {
        self.token = token
        self.monospacedDigits = monospacedDigits
        _size = ScaledMetric(wrappedValue: token.size, relativeTo: token.relativeTo)
    }

    func body(content: Content) -> some View {
        content
            .font(token.font(size: size, monospacedDigits: monospacedDigits))
            .tracking(token.tracking)
    }
}

extension View {
    /// Шрифт-токен. `digits: true` — табличные цифры для сумм.
    func monoFont(_ token: FontToken, digits: Bool = false) -> some View {
        modifier(MonoFontModifier(token: token, monospacedDigits: digits))
    }
}

/// Надпись-«кикер»: SF Pro Expanded, капс, разрядка. Главный признак редакционной вёрстки MONO.
struct Kicker: View {
    let text: LocalizedStringKey
    var color: Color = Color.mono.textTertiary

    init(_ text: LocalizedStringKey, color: Color = Color.mono.textTertiary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .monoFont(.kicker)
            .foregroundStyle(color)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Заголовок секции: кикер + заголовок серифом + необязательное действие справа.
struct SectionHeader<Trailing: View>: View {
    let kicker: LocalizedStringKey
    let title: LocalizedStringKey?
    let trailing: Trailing

    init(kicker: LocalizedStringKey, title: LocalizedStringKey? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.kicker = kicker
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Kicker(kicker)
                if let title {
                    Text(title)
                        .monoFont(.title)
                        .foregroundStyle(Color.mono.textPrimary)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(kicker: LocalizedStringKey, title: LocalizedStringKey? = nil) {
        self.init(kicker: kicker, title: title) { EmptyView() }
    }
}
