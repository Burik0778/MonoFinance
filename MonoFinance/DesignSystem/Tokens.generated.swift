// Сгенерировано Tools/generate_tokens.py из Design/tokens.json — не редактируйте вручную.
import SwiftUI

enum MonoTokens {
    enum Palette {
        /// Фон приложения
        static let background = DynamicColor(dark: RGBA(0, 0, 0, 1.000), light: RGBA(242, 242, 244, 1.000))
        /// Фон листов и шторок
        static let backgroundRaised = DynamicColor(dark: RGBA(12, 12, 13, 1.000), light: RGBA(236, 236, 239, 1.000))
        /// Поверхность: карточки и списки
        static let surface1 = DynamicColor(dark: RGBA(18, 18, 20, 1.000), light: RGBA(255, 255, 255, 1.000))
        /// Вложенные блоки, поля, нажатое состояние
        static let surface2 = DynamicColor(dark: RGBA(27, 27, 30, 1.000), light: RGBA(244, 244, 246, 1.000))
        /// Чипы, дорожки прогресса, плитки значков
        static let surface3 = DynamicColor(dark: RGBA(38, 38, 42, 1.000), light: RGBA(228, 228, 232, 1.000))
        /// Волосяные разделители
        static let strokeSubtle = DynamicColor(dark: RGBA(255, 255, 255, 0.039), light: RGBA(0, 0, 0, 0.051))
        /// Контуры полей, фокус
        static let strokeStrong = DynamicColor(dark: RGBA(255, 255, 255, 0.090), light: RGBA(0, 0, 0, 0.102))
        /// Основной текст и суммы
        static let textPrimary = DynamicColor(dark: RGBA(255, 255, 255, 1.000), light: RGBA(10, 10, 11, 1.000))
        /// Вторичный текст
        static let textSecondary = DynamicColor(dark: RGBA(161, 161, 166, 1.000), light: RGBA(85, 85, 91, 1.000))
        /// Подписи, плейсхолдеры
        static let textTertiary = DynamicColor(dark: RGBA(110, 110, 115, 1.000), light: RGBA(110, 110, 115, 1.000))
        /// Единственный акцент: основные кнопки, выбор, линия графика
        static let accent = DynamicColor(dark: RGBA(255, 255, 255, 1.000), light: RGBA(10, 10, 11, 1.000))
        /// Акцент для текста и значков на тёмной поверхности
        static let accentText = DynamicColor(dark: RGBA(255, 255, 255, 1.000), light: RGBA(10, 10, 11, 1.000))
        /// Текст на акцентной заливке
        static let onAccent = DynamicColor(dark: RGBA(0, 0, 0, 1.000), light: RGBA(255, 255, 255, 1.000))
        /// Доход, рост, достигнутая цель
        static let positive = DynamicColor(dark: RGBA(52, 199, 123, 1.000), light: RGBA(20, 134, 79, 1.000))
        /// Превышение, ошибки, удаление (сдержанный красный)
        static let negative = DynamicColor(dark: RGBA(242, 92, 92, 1.000), light: RGBA(201, 48, 44, 1.000))
        /// Предупреждения, комиссии
        static let warning = DynamicColor(dark: RGBA(245, 165, 36, 1.000), light: RGBA(154, 91, 0, 1.000))
        /// Нейтральная графика: «прочее», прошлый период
        static let neutral = DynamicColor(dark: RGBA(72, 72, 77, 1.000), light: RGBA(176, 176, 182, 1.000))
    }

    enum Chart {
        static let ramp: [DynamicColor] = [DynamicColor(dark: RGBA(242, 242, 244, 1.000), light: RGBA(10, 10, 11, 1.000)), DynamicColor(dark: RGBA(174, 174, 180, 1.000), light: RGBA(74, 74, 80, 1.000)), DynamicColor(dark: RGBA(124, 124, 130, 1.000), light: RGBA(124, 124, 130, 1.000)), DynamicColor(dark: RGBA(90, 90, 95, 1.000), light: RGBA(165, 165, 171, 1.000)), DynamicColor(dark: RGBA(64, 64, 69, 1.000), light: RGBA(200, 200, 205, 1.000)), DynamicColor(dark: RGBA(46, 46, 50, 1.000), light: RGBA(220, 220, 224, 1.000))]
    }

    enum Skin {
        static let aurora: [RGBA] = [RGBA(42, 74, 143, 1.000), RGBA(24, 48, 94, 1.000), RGBA(14, 27, 55, 1.000)]
        static let nebula: [RGBA] = [RGBA(67, 50, 88, 1.000), RGBA(39, 29, 56, 1.000), RGBA(21, 16, 32, 1.000)]
        static let glacier: [RGBA] = [RGBA(58, 76, 99, 1.000), RGBA(36, 50, 68, 1.000), RGBA(20, 28, 39, 1.000)]
        static let lagoon: [RGBA] = [RGBA(33, 82, 72, 1.000), RGBA(21, 51, 45, 1.000), RGBA(11, 28, 25, 1.000)]
        static let graphite: [RGBA] = [RGBA(53, 59, 69, 1.000), RGBA(31, 35, 42, 1.000), RGBA(17, 19, 23, 1.000)]
        static let ultraviolet: [RGBA] = [RGBA(51, 54, 122, 1.000), RGBA(29, 31, 74, 1.000), RGBA(16, 17, 42, 1.000)]
    }

    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 40
        static let huge: CGFloat = 56
    }

    enum Radius {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Typography {
        static let hero = FontToken(size: 52, weight: .bold, style: .default, relativeTo: .largeTitle, tracking: -2.0)
        static let display = FontToken(size: 32, weight: .bold, style: .default, relativeTo: .largeTitle, tracking: -1.0)
        static let title = FontToken(size: 22, weight: .semibold, style: .default, relativeTo: .title, tracking: -0.45)
        static let title2 = FontToken(size: 19, weight: .semibold, style: .default, relativeTo: .title2, tracking: -0.3)
        static let quote = FontToken(size: 17, weight: .regular, style: .default, relativeTo: .title3, tracking: -0.1)
        static let headline = FontToken(size: 16, weight: .semibold, style: .default, relativeTo: .headline, tracking: 0)
        static let body = FontToken(size: 16, weight: .regular, style: .default, relativeTo: .body, tracking: 0)
        static let callout = FontToken(size: 15, weight: .regular, style: .default, relativeTo: .callout, tracking: 0)
        static let subhead = FontToken(size: 14, weight: .medium, style: .default, relativeTo: .subheadline, tracking: 0)
        static let footnote = FontToken(size: 13, weight: .regular, style: .default, relativeTo: .footnote, tracking: 0)
        static let caption = FontToken(size: 12, weight: .medium, style: .default, relativeTo: .caption, tracking: 0)
        static let kicker = FontToken(size: 11, weight: .semibold, style: .expanded, relativeTo: .caption2, tracking: 1.1)
        static let amount = FontToken(size: 28, weight: .bold, style: .default, relativeTo: .title, tracking: -0.9)
        static let amountRow = FontToken(size: 16, weight: .semibold, style: .default, relativeTo: .body, tracking: -0.2)
    }

    enum Motion {
        static let quick = SpringToken(response: 0.26, damping: 0.88)
        static let standard = SpringToken(response: 0.4, damping: 0.85)
        static let emphasized = SpringToken(response: 0.52, damping: 0.78)
        static let gentle = SpringToken(response: 0.7, damping: 0.92)
        static let fadeDuration: Double = 0.18
    }
}
