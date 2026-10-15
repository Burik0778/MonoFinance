// Сгенерировано Tools/generate_tokens.py из Design/tokens.json — не редактируйте вручную.
import SwiftUI

enum MonoTokens {
    enum Palette {
        /// Фон приложения
        static let background = DynamicColor(dark: RGBA(9, 13, 20, 1.000), light: RGBA(243, 245, 248, 1.000))
        /// Фон листов и шторок
        static let backgroundRaised = DynamicColor(dark: RGBA(13, 18, 27, 1.000), light: RGBA(235, 238, 243, 1.000))
        /// Поверхность: карточки и списки
        static let surface1 = DynamicColor(dark: RGBA(18, 25, 37, 1.000), light: RGBA(255, 255, 255, 1.000))
        /// Вложенные блоки, поля, нажатое состояние
        static let surface2 = DynamicColor(dark: RGBA(24, 33, 49, 1.000), light: RGBA(246, 247, 250, 1.000))
        /// Чипы, дорожки прогресса, плитки значков
        static let surface3 = DynamicColor(dark: RGBA(32, 43, 61, 1.000), light: RGBA(231, 235, 241, 1.000))
        /// Волосяные разделители
        static let strokeSubtle = DynamicColor(dark: RGBA(255, 255, 255, 0.055), light: RGBA(11, 16, 24, 0.063))
        /// Контуры полей, фокус
        static let strokeStrong = DynamicColor(dark: RGBA(255, 255, 255, 0.110), light: RGBA(11, 16, 24, 0.133))
        /// Основной текст и суммы
        static let textPrimary = DynamicColor(dark: RGBA(234, 240, 247, 1.000), light: RGBA(11, 16, 24, 1.000))
        /// Вторичный текст
        static let textSecondary = DynamicColor(dark: RGBA(155, 167, 185, 1.000), light: RGBA(74, 84, 101, 1.000))
        /// Подписи, плейсхолдеры
        static let textTertiary = DynamicColor(dark: RGBA(113, 125, 145, 1.000), light: RGBA(104, 114, 133, 1.000))
        /// Единственный акцент: основные кнопки, выбор, линия графика
        static let accent = DynamicColor(dark: RGBA(61, 112, 224, 1.000), light: RGBA(46, 98, 214, 1.000))
        /// Акцент для текста и значков на тёмной поверхности
        static let accentText = DynamicColor(dark: RGBA(134, 168, 244, 1.000), light: RGBA(37, 86, 196, 1.000))
        /// Текст на акцентной заливке
        static let onAccent = DynamicColor(dark: RGBA(255, 255, 255, 1.000), light: RGBA(255, 255, 255, 1.000))
        /// Доход, рост, достигнутая цель
        static let positive = DynamicColor(dark: RGBA(39, 181, 140, 1.000), light: RGBA(15, 125, 93, 1.000))
        /// Превышение, ошибки, удаление (сдержанный красный)
        static let negative = DynamicColor(dark: RGBA(224, 103, 110, 1.000), light: RGBA(194, 52, 62, 1.000))
        /// Предупреждения, комиссии
        static let warning = DynamicColor(dark: RGBA(217, 165, 90, 1.000), light: RGBA(148, 101, 15, 1.000))
        /// Нейтральная графика: «прочее», прошлый период
        static let neutral = DynamicColor(dark: RGBA(92, 104, 124, 1.000), light: RGBA(154, 163, 178, 1.000))
    }

    enum Chart {
        static let ramp: [DynamicColor] = [DynamicColor(dark: RGBA(94, 141, 242, 1.000), light: RGBA(46, 98, 214, 1.000)), DynamicColor(dark: RGBA(47, 87, 184, 1.000), light: RGBA(127, 162, 236, 1.000)), DynamicColor(dark: RGBA(163, 188, 246, 1.000), light: RGBA(23, 62, 148, 1.000)), DynamicColor(dark: RGBA(62, 111, 217, 1.000), light: RGBA(79, 127, 226, 1.000)), DynamicColor(dark: RGBA(34, 57, 110, 1.000), light: RGBA(183, 203, 244, 1.000)), DynamicColor(dark: RGBA(125, 139, 163, 1.000), light: RGBA(140, 150, 168, 1.000))]
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
        static let hero = FontToken(size: 46, weight: .semibold, style: .default, relativeTo: .largeTitle, tracking: -1.4)
        static let display = FontToken(size: 32, weight: .bold, style: .default, relativeTo: .largeTitle, tracking: -0.8)
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
        static let amount = FontToken(size: 28, weight: .semibold, style: .default, relativeTo: .title, tracking: -0.7)
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
