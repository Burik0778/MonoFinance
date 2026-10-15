import SwiftUI
import MonoCore

/// Генеративный фон виртуальной карты: сетчатый градиент + «гравировка» из дуг + мягкий блик.
/// Не повторяет дизайн реальных банковских карт: только абстрактный скин, название банка текстом и последние цифры.
struct CardSkinBackground: View {
    let skin: CardSkin

    var body: some View {
        let c = skin.colors
        ZStack {
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.55, 0], [1, 0],
                    [0, 0.5], [0.62, 0.42], [1, 0.55],
                    [0, 1], [0.45, 1], [1, 1]
                ],
                colors: [
                    c[0], c[0], c[1],
                    c[0], c[1], c[2],
                    c[1], c[2], c[2]
                ]
            )
            Canvas { context, size in
                let origin = CGPoint(x: size.width * 0.92, y: -size.height * 0.1)
                for index in 0..<11 {
                    let radius = size.width * (0.18 + CGFloat(index) * 0.075)
                    let rect = CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2)
                    context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.07)), lineWidth: 0.8)
                }
            }
            LinearGradient(colors: [.white.opacity(0.20), .clear, .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .blendMode(.softLight)
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

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style == .full ? MonoTokens.Radius.xl : MonoTokens.Radius.lg, style: .continuous)
        ZStack(alignment: .topLeading) {
            CardSkinBackground(skin: account.skin)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: account.bank.displayName)
                        .monoFont(style == .full ? .subhead : .caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(verbatim: account.paymentSystem?.label ?? account.kind.title(.current).uppercased())
                        .monoFont(.kicker)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                Spacer(minLength: style == .full ? 18 : 10)
                MoneyText(money: balance, token: style == .full ? .amount : .headline, color: .white)
                Spacer(minLength: style == .full ? 14 : 6)
                HStack {
                    Text(verbatim: account.displayName)
                        .monoFont(style == .full ? .callout : .footnote)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let masked = account.maskedNumber {
                        Text(verbatim: masked)
                            .monoFont(style == .full ? .callout : .footnote, digits: true)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .padding(style == .full ? 20 : 14)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: account.tint.opacity(0.35), radius: style == .full ? 26 : 14, x: 0, y: style == .full ? 16 : 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(account.bank.displayName), \(account.displayName)"))
    }
}
