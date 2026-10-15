import SwiftUI

/// Поверхность: плоская графитовая заливка и волосяной контур. Без свечений; глубина — только от разницы тонов.
/// В режиме повышенного контраста контур становится заметнее.
struct MonoSurface: ViewModifier {
    var level: Int = 1
    var radius: CGFloat = MonoTokens.Radius.lg
    var padding: CGFloat? = MonoTokens.Spacing.md
    var fill: Color?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding ?? 0)
            .background(shape.fill(fill ?? (level >= 2 ? Color.mono.surface2 : Color.mono.surface1)))
            .overlay {
                shape.strokeBorder(contrast == .increased ? Color.mono.strokeStrong : Color.mono.strokeSubtle,
                                   lineWidth: contrast == .increased ? 1.5 : 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 12, x: 0, y: 4)
    }
}

extension View {
    func monoSurface(level: Int = 1, radius: CGFloat = MonoTokens.Radius.lg, padding: CGFloat? = MonoTokens.Spacing.md, fill: Color? = nil) -> some View {
        modifier(MonoSurface(level: level, radius: radius, padding: padding, fill: fill))
    }

    /// Тонкий разделитель-«волосок».
    func hairlineDivider() -> some View {
        overlay(alignment: .bottom) {
            Rectangle().fill(Color.mono.strokeSubtle).frame(height: 1)
        }
    }
}

/// Волосяная линия между строками.
struct Hairline: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.mono.strokeSubtle)
            .frame(height: 1)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

/// Капсула-чип (фильтры, теги, быстрые исправления). Выбранный — мягкая акцентная подложка, а не яркая заливка.
struct ChipStyle: ButtonStyle {
    var isSelected = false
    var tint: Color = Color.mono.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .monoFont(.subhead)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.mono.textPrimary : Color.mono.textSecondary)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(tint.opacity(0.22)) : AnyShapeStyle(Color.mono.surface2))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? tint.opacity(0.55) : Color.mono.strokeSubtle, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(SpringToken.quick.animation, value: configuration.isPressed)
    }
}

/// Основная кнопка: сплошной акцент. Одна такая кнопка на экран.
/// `colors` оставлен для совместимости вызовов и не используется: у MONO один акцент.
struct PrimaryButtonStyle: ButtonStyle {
    var colors: [Color] = []
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .monoFont(.headline)
            .foregroundStyle(isEnabled ? Color.mono.onAccent : Color.mono.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous)
                    .fill(isEnabled ? Color.mono.accent : Color.mono.surface3)
                    .brightness(configuration.isPressed ? -0.06 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous)
                    .strokeBorder(Color.white.opacity(isEnabled ? 0.10 : 0), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(SpringToken.quick.animation, value: configuration.isPressed)
            .animation(SpringToken.quick.animation, value: isEnabled)
    }
}

/// Вторичная кнопка на поверхности.
struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Color.mono.textPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .monoFont(.headline)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(configuration.isPressed ? Color.mono.surface3 : Color.mono.surface2))
            .overlay(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).strokeBorder(Color.mono.strokeSubtle, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(SpringToken.quick.animation, value: configuration.isPressed)
    }
}

/// Круглая иконка-кнопка (шапки экранов).
struct IconButton: View {
    let systemName: String
    let label: LocalizedStringKey
    var tint: Color = Color.mono.textPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.mono.surface1))
                .overlay(Circle().strokeBorder(Color.mono.strokeSubtle, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(label)
    }
}

/// Текстовая ссылка в заголовке секции («Все», «Аналитика»).
struct SectionLink: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .monoFont(.subhead)
            .foregroundStyle(Color.mono.accentText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
