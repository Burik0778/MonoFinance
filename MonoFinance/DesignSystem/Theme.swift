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

/// Палитра «Midnight Ledger».
struct MonoColors {
    let background = MonoTokens.Palette.background.color
    let backgroundRaised = MonoTokens.Palette.backgroundRaised.color
    let surface1 = MonoTokens.Palette.surface1.color
    let surface2 = MonoTokens.Palette.surface2.color
    let surface3 = MonoTokens.Palette.surface3.color
    let strokeSubtle = MonoTokens.Palette.strokeSubtle.color
    let strokeStrong = MonoTokens.Palette.strokeStrong.color
    let rimTop = MonoTokens.Palette.rimTop.color
    let rimBottom = MonoTokens.Palette.rimBottom.color
    let textPrimary = MonoTokens.Palette.textPrimary.color
    let textSecondary = MonoTokens.Palette.textSecondary.color
    let textTertiary = MonoTokens.Palette.textTertiary.color
    let electric = MonoTokens.Palette.electric.color
    let violet = MonoTokens.Palette.violet.color
    let cyan = MonoTokens.Palette.cyan.color
    let emerald = MonoTokens.Palette.emerald.color
    let coral = MonoTokens.Palette.coral.color
    let magenta = MonoTokens.Palette.magenta.color
    let indigo = MonoTokens.Palette.indigo.color
    let sky = MonoTokens.Palette.sky.color
    let mint = MonoTokens.Palette.mint.color
    let tangerine = MonoTokens.Palette.tangerine.color
    let rose = MonoTokens.Palette.rose.color
    let steel = MonoTokens.Palette.steel.color

    /// Семантика
    var positive: Color { emerald }
    var negative: Color { coral }
    var warning: Color { tangerine }
    var accent: Color { electric }

    /// Фирменный градиент голосового ввода.
    var voiceGradient: [Color] { [electric, violet, cyan] }
}

extension Color {
    static let mono = MonoColors()
}

extension ShapeStyle where Self == Color {
    static var monoPrimary: Color { Color.mono.textPrimary }
    static var monoSecondary: Color { Color.mono.textSecondary }
    static var monoTertiary: Color { Color.mono.textTertiary }
}

extension CategoryColor {
    var color: Color {
        switch self {
        case .electric: return Color.mono.electric
        case .violet: return Color.mono.violet
        case .cyan: return Color.mono.cyan
        case .emerald: return Color.mono.emerald
        case .coral: return Color.mono.coral
        case .magenta: return Color.mono.magenta
        case .indigo: return Color.mono.indigo
        case .sky: return Color.mono.sky
        case .mint: return Color.mono.mint
        case .tangerine: return Color.mono.tangerine
        case .rose: return Color.mono.rose
        case .steel: return Color.mono.steel
        }
    }
}

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

    /// Цвет счёта в графиках и полосе ликвидности.
    var tint: Color {
        switch self {
        case .graphite: return Color.mono.steel
        default: return stops[stops.count / 2].color
        }
    }

    var linearGradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var title: LocalizedStringKey {
        switch self {
        case .aurora: return "Аврора"
        case .nebula: return "Туманность"
        case .glacier: return "Ледник"
        case .lagoon: return "Лагуна"
        case .graphite: return "Графит"
        case .ultraviolet: return "Ультрафиолет"
        }
    }
}

extension Account {
    var tint: Color { skin.tint }
}

/// Цвет суммы по знаку и типу операции.
extension TransactionKind {
    var tint: Color {
        switch self {
        case .income, .refund: return Color.mono.emerald
        case .expense: return Color.mono.textPrimary
        case .fee: return Color.mono.tangerine
        case .transfer: return Color.mono.sky
        case .adjustment: return Color.mono.steel
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
