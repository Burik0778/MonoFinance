import SwiftUI
import UIKit
import MonoCore

/// Цвет в sRGB (компоненты 0…1).
struct RGBA: Sendable, Hashable {
    let r: Double
    let g: Double
    let b: Double
    let a: Double

    init(_ r: Int, _ g: Int, _ b: Int, _ a: Double) {
        self.r = Double(r) / 255
        self.g = Double(g) / 255
        self.b = Double(b) / 255
        self.a = a
    }

    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

/// Цвет, меняющийся с темой. Основной режим — тёмный: всё, что не «светлое», рисуется тёмной палитрой.
struct DynamicColor: Sendable {
    let dark: RGBA
    let light: RGBA

    var color: Color {
        let dark = self.dark
        let light = self.light
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .light ? light.uiColor : dark.uiColor
        })
    }
}

/// Палитра «Graphite»: графитовые поверхности, один акцент, сдержанная семантика.
/// Правило: цвет несёт смысл. Акцент — действие и выбор; зелёный/красный — только знак суммы и статус.
struct MonoColors {
    let background = MonoTokens.Palette.background.color
    let backgroundRaised = MonoTokens.Palette.backgroundRaised.color
    let surface1 = MonoTokens.Palette.surface1.color
    let surface2 = MonoTokens.Palette.surface2.color
    let surface3 = MonoTokens.Palette.surface3.color
    let strokeSubtle = MonoTokens.Palette.strokeSubtle.color
    let strokeStrong = MonoTokens.Palette.strokeStrong.color
    let textPrimary = MonoTokens.Palette.textPrimary.color
    let textSecondary = MonoTokens.Palette.textSecondary.color
    let textTertiary = MonoTokens.Palette.textTertiary.color
    /// Заливка основных кнопок, выбранное состояние, линия графика.
    let accent = MonoTokens.Palette.accent.color
    /// Акцент для текста и значков (ссылки «Все», активные иконки) — контрастнее на тёмном.
    let accentText = MonoTokens.Palette.accentText.color
    let onAccent = MonoTokens.Palette.onAccent.color
    let positive = MonoTokens.Palette.positive.color
    let negative = MonoTokens.Palette.negative.color
    let warning = MonoTokens.Palette.warning.color
    /// Нейтральная графика: «прочее», прошлый период, архив.
    let neutral = MonoTokens.Palette.neutral.color

    /// Мягкая подложка акцента (выбранный чип, фон значка действия).
    var accentWash: Color { accent.opacity(0.16) }

    /// Ступени акцента для категорий и серий в графиках (по рангу, а не по «цвету категории»).
    func chart(_ index: Int) -> Color {
        let ramp = MonoTokens.Chart.ramp
        guard index >= 0 else { return neutral }
        return ramp[min(index, ramp.count - 1)].color
    }
}

extension Color {
    static let mono = MonoColors()
}

extension ShapeStyle where Self == Color {
    static var monoPrimary: Color { Color.mono.textPrimary }
    static var monoSecondary: Color { Color.mono.textSecondary }
    static var monoTertiary: Color { Color.mono.textTertiary }
}

/// Цвет категории — приглушённый тон. Показывается только там, где пользователь выбирает или узнаёт категорию
/// (редактор, список категорий, цели). В списках операций значки монохромные.
extension CategoryColor {
    var color: Color { tone.color }

    var tone: DynamicColor {
        switch self {
        case .electric: return DynamicColor(dark: RGBA(134, 165, 232, 1), light: RGBA(46, 86, 180, 1))
        case .violet: return DynamicColor(dark: RGBA(160, 150, 214, 1), light: RGBA(92, 78, 160, 1))
        case .cyan: return DynamicColor(dark: RGBA(128, 178, 196, 1), light: RGBA(36, 110, 132, 1))
        case .emerald: return DynamicColor(dark: RGBA(112, 182, 156, 1), light: RGBA(24, 116, 84, 1))
        case .coral: return DynamicColor(dark: RGBA(214, 150, 142, 1), light: RGBA(160, 68, 60, 1))
        case .magenta: return DynamicColor(dark: RGBA(192, 150, 196, 1), light: RGBA(128, 70, 132, 1))
        case .indigo: return DynamicColor(dark: RGBA(146, 154, 216, 1), light: RGBA(70, 80, 160, 1))
        case .sky: return DynamicColor(dark: RGBA(138, 172, 210, 1), light: RGBA(44, 100, 156, 1))
        case .mint: return DynamicColor(dark: RGBA(134, 192, 174, 1), light: RGBA(30, 120, 98, 1))
        case .tangerine: return DynamicColor(dark: RGBA(208, 170, 128, 1), light: RGBA(140, 92, 36, 1))
        case .rose: return DynamicColor(dark: RGBA(206, 152, 170, 1), light: RGBA(150, 64, 96, 1))
        case .steel: return DynamicColor(dark: RGBA(150, 162, 182, 1), light: RGBA(86, 98, 120, 1))
        }
    }
}

/// Материал виртуальной карты. Имена кейсов хранятся в базе, поэтому остаются прежними; меняется только вид:
/// вместо кислотных градиентов — глубокие тёмные «металлы».
extension CardSkin {
    var stops: [RGBA] {
        switch self {
        case .aurora: return MonoTokens.Skin.aurora
        case .nebula: return MonoTokens.Skin.nebula
        case .glacier: return MonoTokens.Skin.glacier
        case .lagoon: return MonoTokens.Skin.lagoon
        case .graphite: return MonoTokens.Skin.graphite
        case .ultraviolet: return MonoTokens.Skin.ultraviolet
        }
    }

    var colors: [Color] { stops.map(\.color) }

    /// Цвет-метка счёта (миниатюры, точки в списках). Самая светлая ступень материала.
    var tint: Color { stops[0].color }

    var linearGradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var title: LocalizedStringKey {
        switch self {
        case .aurora: return "Кобальт"
        case .nebula: return "Слива"
        case .glacier: return "Сталь"
        case .lagoon: return "Хвоя"
        case .graphite: return "Графит"
        case .ultraviolet: return "Индиго"
        }
    }
}

extension Account {
    var tint: Color { skin.tint }
}

/// Цвет суммы по типу операции: доход и возврат — зелёным, остальное — нейтрально.
extension TransactionKind {
    var tint: Color {
        switch self {
        case .income, .refund: return Color.mono.positive
        case .expense: return Color.mono.textPrimary
        case .fee: return Color.mono.textPrimary
        case .transfer: return Color.mono.textSecondary
        case .adjustment: return Color.mono.textSecondary
        }
    }

    var symbol: String {
        switch self {
        case .expense: return "arrow.up.right"
        case .income: return "arrow.down.left"
        case .transfer: return "arrow.left.arrow.right"
        case .fee: return "percent"
        case .refund: return "arrow.uturn.backward"
        case .adjustment: return "slider.horizontal.3"
        }
    }
}
