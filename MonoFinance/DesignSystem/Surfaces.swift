import SwiftUI

/// Поверхность карточки: заливка, «световая кромка» сверху, мягкая тень. В режиме повышенного контраста — чёткий контур.
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
                if contrast == .increased {
                    shape.strokeBorder(Color.mono.strokeStrong, lineWidth: 1.5)
                } else {
                    shape.strokeBorder(
                        LinearGradient(colors: [Color.mono.rimTop, Color.mono.rimBottom], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                }
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.07), radius: level >= 2 ? 26 : 16, x: 0, y: level >= 2 ? 16 : 8)
    }
}

extension View {
    func monoSurface(level: Int = 1, radius: CGFloat = MonoTokens.Radius.lg, padding: CGFloat? = MonoTokens.Spacing.md, fill: Color? = nil) -> some View {
        modifier(MonoSurface(level: level, radius: radius, padding: padding, fill: fill))
    }

    /// Локальное свечение под элементом — только там, где оно что-то значит.
    func glow(_ color: Color, radius: CGFloat = 24, opacity: Double = 0.45) -> some View {
        background {
            self.blur(radius: radius).opacity(opacity).foregroundStyle(color)
        }
    }

    /// Тонкий разделитель-«волосок».
    func hairlineDivider() -> some View {
        overlay(alignment: .bottom) {
            Rectangle().fill(Color.mono.strokeSubtle).frame(height: 1)
        }
    }
}

/// Капсула-чип (фильтры, теги, быстрые исправления).
struct ChipStyle: ButtonStyle {
    var isSelected = false
    var tint: Color = Color.mono.electric

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .monoFont(.subhead)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.white : Color.mono.textPrimary)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(Color.mono.surface3))
            )
            .overlay(Capsule(style: .continuous).strokeBorder(Color.mono.strokeSubtle, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(SpringToken.quick.animation, value: configuration.isPressed)
    }
}

/// Основная кнопка: насыщенный градиент, крупная надпись.
struct PrimaryButtonStyle: ButtonStyle {
    var colors: [Color] = [Color.mono.electric, Color.mono.violet]
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .monoFont(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .opacity(isEnabled ? 1 : 0.35)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(SpringToken.quick.animation, value: configuration.isPressed)
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
            .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.surface3))
            .overlay(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).strokeBorder(Color.mono.strokeSubtle, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.mono.surface2))
                .overlay(Circle().strokeBorder(Color.mono.strokeSubtle, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(label)
    }
}
