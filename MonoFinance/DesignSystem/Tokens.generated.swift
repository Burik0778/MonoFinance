// Сгенерировано Tools/generate_tokens.py из Design/tokens.json — не редактируйте вручную.
import SwiftUI

enum MonoTokens {
    enum Palette {
        /// Фон приложения
        static let background = DynamicColor(dark: RGBA(5, 7, 13, 1.000), light: RGBA(244, 246, 251, 1.000))
        /// Фон листов и шторок
        static let backgroundRaised = DynamicColor(dark: RGBA(10, 14, 25, 1.000), light: RGBA(236, 239, 247, 1.000))
        /// Карточки
        static let surface1 = DynamicColor(dark: RGBA(15, 20, 34, 1.000), light: RGBA(255, 255, 255, 1.000))
        /// Вложенные блоки, нажатое состояние
        static let surface2 = DynamicColor(dark: RGBA(21, 27, 45, 1.000), light: RGBA(247, 248, 252, 1.000))
        /// Поля ввода, чипы
        static let surface3 = DynamicColor(dark: RGBA(28, 36, 56, 1.000), light: RGBA(233, 237, 246, 1.000))
        /// Тонкие разделители
        static let strokeSubtle = DynamicColor(dark: RGBA(255, 255, 255, 0.059), light: RGBA(10, 14, 26, 0.071))
        /// Контуры полей
        static let strokeStrong = DynamicColor(dark: RGBA(255, 255, 255, 0.122), light: RGBA(10, 14, 26, 0.141))
        /// Световая кромка сверху
        static let rimTop = DynamicColor(dark: RGBA(255, 255, 255, 0.149), light: RGBA(255, 255, 255, 1.000))
        /// Кромка снизу
        static let rimBottom = DynamicColor(dark: RGBA(255, 255, 255, 0.020), light: RGBA(10, 14, 26, 0.039))
        /// Основной текст
        static let textPrimary = DynamicColor(dark: RGBA(244, 246, 251, 1.000), light: RGBA(10, 14, 26, 1.000))
        /// Вторичный текст
        static let textSecondary = DynamicColor(dark: RGBA(163, 172, 194, 1.000), light: RGBA(74, 84, 112, 1.000))
        /// Подписи, плейсхолдеры
        static let textTertiary = DynamicColor(dark: RGBA(122, 132, 160, 1.000), light: RGBA(106, 115, 144, 1.000))
        /// Основной акцент
        static let electric = DynamicColor(dark: RGBA(65, 112, 255, 1.000), light: RGBA(47, 91, 255, 1.000))
        /// Акцент, голос
        static let violet = DynamicColor(dark: RGBA(143, 99, 255, 1.000), light: RGBA(116, 69, 245, 1.000))
        /// Акцент, графики
        static let cyan = DynamicColor(dark: RGBA(51, 218, 245, 1.000), light: RGBA(10, 143, 176, 1.000))
        /// Доход, положительное
        static let emerald = DynamicColor(dark: RGBA(34, 219, 156, 1.000), light: RGBA(14, 159, 110, 1.000))
        /// Расход, отрицательное
        static let coral = DynamicColor(dark: RGBA(255, 92, 124, 1.000), light: RGBA(229, 57, 98, 1.000))
        /// Категории
        static let magenta = DynamicColor(dark: RGBA(227, 91, 255, 1.000), light: RGBA(182, 53, 214, 1.000))
        /// Категории
        static let indigo = DynamicColor(dark: RGBA(100, 112, 255, 1.000), light: RGBA(75, 85, 230, 1.000))
        /// Категории
        static let sky = DynamicColor(dark: RGBA(79, 176, 255, 1.000), light: RGBA(30, 134, 224, 1.000))
        /// Категории
        static let mint = DynamicColor(dark: RGBA(76, 230, 195, 1.000), light: RGBA(16, 156, 128, 1.000))
        /// Предупреждение
        static let tangerine = DynamicColor(dark: RGBA(255, 139, 77, 1.000), light: RGBA(224, 102, 31, 1.000))
        /// Категории
        static let rose = DynamicColor(dark: RGBA(255, 114, 168, 1.000), light: RGBA(217, 64, 125, 1.000))
        /// Нейтральные категории
        static let steel = DynamicColor(dark: RGBA(133, 146, 176, 1.000), light: RGBA(94, 106, 135, 1.000))
    }

    enum Skin {
        static let aurora: [RGBA] = [RGBA(36, 69, 255, 1.000), RGBA(91, 59, 255, 1.000), RGBA(155, 77, 255, 1.000)]
        static let nebula: [RGBA] = [RGBA(74, 31, 184, 1.000), RGBA(162, 60, 240, 1.000), RGBA(255, 95, 191, 1.000)]
        static let glacier: [RGBA] = [RGBA(15, 87, 232, 1.000), RGBA(30, 155, 240, 1.000), RGBA(62, 227, 245, 1.000)]
        static let lagoon: [RGBA] = [RGBA(10, 143, 134, 1.000), RGBA(19, 201, 154, 1.000), RGBA(61, 134, 255, 1.000)]
        static let graphite: [RGBA] = [RGBA(21, 26, 42, 1.000), RGBA(35, 43, 68, 1.000), RGBA(50, 60, 92, 1.000)]
        static let ultraviolet: [RGBA] = [RGBA(58, 20, 201, 1.000), RGBA(123, 60, 255, 1.000), RGBA(255, 92, 154, 1.000)]
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
        static let md: CGFloat = 16
        static let lg: CGFloat = 22
        static let xl: CGFloat = 28
        static let xxl: CGFloat = 36
    }

    enum Typography {
        static let hero = FontToken(size: 52, weight: .semibold, style: .serif, relativeTo: .largeTitle, tracking: 0)
        static let display = FontToken(size: 34, weight: .semibold, style: .serif, relativeTo: .largeTitle, tracking: 0)
        static let title = FontToken(size: 26, weight: .semibold, style: .serif, relativeTo: .title, tracking: 0)
        static let title2 = FontToken(size: 21, weight: .semibold, style: .default, relativeTo: .title2, tracking: 0)
        static let quote = FontToken(size: 20, weight: .medium, style: .serif, relativeTo: .title3, tracking: 0)
        static let headline = FontToken(size: 17, weight: .semibold, style: .default, relativeTo: .headline, tracking: 0)
        static let body = FontToken(size: 17, weight: .regular, style: .default, relativeTo: .body, tracking: 0)
        static let callout = FontToken(size: 15, weight: .regular, style: .default, relativeTo: .callout, tracking: 0)
        static let subhead = FontToken(size: 14, weight: .medium, style: .default, relativeTo: .subheadline, tracking: 0)
        static let footnote = FontToken(size: 13, weight: .regular, style: .default, relativeTo: .footnote, tracking: 0)
        static let caption = FontToken(size: 12, weight: .medium, style: .default, relativeTo: .caption, tracking: 0)
        static let kicker = FontToken(size: 11, weight: .semibold, style: .expanded, relativeTo: .caption2, tracking: 1.4)
        static let amount = FontToken(size: 28, weight: .semibold, style: .serif, relativeTo: .title, tracking: 0)
        static let amountRow = FontToken(size: 16, weight: .semibold, style: .rounded, relativeTo: .body, tracking: 0)
    }

    enum Motion {
        static let quick = SpringToken(response: 0.28, damping: 0.86)
        static let standard = SpringToken(response: 0.42, damping: 0.82)
        static let emphasized = SpringToken(response: 0.55, damping: 0.74)
        static let gentle = SpringToken(response: 0.8, damping: 0.92)
        static let fadeDuration: Double = 0.18
    }
}
