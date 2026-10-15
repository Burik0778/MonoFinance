import SwiftUI
import MonoCore

/// Материал виртуальной карты: глубокий тёмный градиент, тонкая гильоширная гравировка и холодный блик по кромке.
/// Не повторяет дизайн реальных банковских карт: только абстрактный материал, название банка текстом и последние цифры.
struct CardSkinBackground: View {
    let skin: CardSkin

    var body: some View {
        let c = skin.colors
        ZStack {
            LinearGradient(colors: c, startPoint: .topLeading, endPoint: .bottomTrailing)
            // Гравировка: тонкие концентрические дуги из правого нижнего угла.
            Canvas { context, size in
                let origin = CGPoint(x: size.width * 1.05, y: size.height * 1.15)
                for index in 0..<18 {
                    let radius = size.width * (0.22 + CGFloat(index) * 0.045)
                    let rect = CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2)
                    context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.045)), lineWidth: 0.6)
                }
            }
            // Мягкий свет сверху слева — «металл», а не неон.
            RadialGradient(colors: [.white.opacity(0.10), .clear], center: .topLeading, startRadius: 0, endRadius: 260)
        }
    }
}

/// Виртуальная карта счёта.
struct VirtualCardView: View {
    let account: Account
    let balance: Money
    var style: Style = .full

    enum Style {
        case full
        case compact
    }

    @Environment(\.appLanguage) private var language

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style == .full ? MonoTokens.Radius.xl : MonoTokens.Radius.lg, style: .continuous)
        ZStack(alignment: .topLeading) {
            CardSkinBackground(skin: account.skin)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: account.bank.displayName)
                        .monoFont(style == .full ? .headline : .subhead)
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(verbatim: account.paymentSystem?.label ?? account.kind.title(language).uppercased())
                        .monoFont(.kicker)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                if style == .full {
                    CardChip()
                        .padding(.top, 18)
                }
                Spacer(minLength: style == .full ? 12 : 8)
                Text(style == .full ? "Доступно" : "Баланс")
                    .monoFont(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                MoneyText(money: balance, token: style == .full ? .amount : .title2, color: .white)
                    .padding(.top, 2)
                Spacer(minLength: style == .full ? 12 : 6)
                HStack {
                    Text(verbatim: account.displayName)
                        .monoFont(style == .full ? .subhead : .caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let masked = account.maskedNumber {
                        Text(verbatim: masked)
                            .monoFont(style == .full ? .subhead : .caption, digits: true)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            .padding(style == .full ? 22 : 16)
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            )
        )
        .shadow(color: .black.opacity(0.35), radius: style == .full ? 22 : 12, x: 0, y: style == .full ? 12 : 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(account.bank.displayName), \(account.displayName)"))
    }
}

/// Минималистичный чип карты — нейтральный металл без бликов.
struct CardChip: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [Color.white.opacity(0.30), Color.white.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Canvas { context, size in
                var path = Path()
                path.move(to: CGPoint(x: size.width * 0.38, y: 0))
                path.addLine(to: CGPoint(x: size.width * 0.38, y: size.height))
                path.move(to: CGPoint(x: size.width * 0.62, y: 0))
                path.addLine(to: CGPoint(x: size.width * 0.62, y: size.height))
                path.move(to: CGPoint(x: 0, y: size.height * 0.5))
                path.addLine(to: CGPoint(x: size.width, y: size.height * 0.5))
                context.stroke(path, with: .color(.black.opacity(0.25)), lineWidth: 0.7)
            }
            shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6)
        }
        .frame(width: 34, height: 26)
        .accessibilityHidden(true)
    }
}

/// Миниатюра карты для строк списков.
struct CardThumbnail: View {
    let skin: CardSkin
    var width: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
        CardSkinBackground(skin: skin)
            .frame(width: width, height: width / 1.586)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8))
            .accessibilityHidden(true)
    }
}
