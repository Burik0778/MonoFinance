import SwiftUI
import UIKit

/// Пружинная анимация-токен.
struct SpringToken: Sendable {
    let response: Double
    let damping: Double

    static let quick = MonoTokens.Motion.quick
    static let standard = MonoTokens.Motion.standard
    static let emphasized = MonoTokens.Motion.emphasized
    static let gentle = MonoTokens.Motion.gentle

    var animation: Animation { .spring(response: response, dampingFraction: damping) }
}

enum Motion {
    /// Анимация с учётом «Уменьшения движения»: вместо пружин — короткое затухание.
    static func animation(_ token: SpringToken, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: MonoTokens.Motion.fadeDuration) : token.animation
    }

    @MainActor
    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
}

/// `withAnimation` с токеном и уважением к Reduce Motion.
@MainActor
func withMonoAnimation<Result>(_ token: SpringToken = .standard, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(Motion.animation(token, reduceMotion: Motion.reduceMotion), body)
}

private struct MonoAnimationModifier<Value: Equatable>: ViewModifier {
    let token: SpringToken
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(Motion.animation(token, reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    func monoAnimation<Value: Equatable>(_ token: SpringToken = .standard, value: Value) -> some View {
        modifier(MonoAnimationModifier(token: token, value: value))
    }
}

/// Появление снизу с размытием — для карточек при первом показе.
struct RiseInModifier: ViewModifier {
    let delay: Double
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 14)
            .blur(radius: visible || reduceMotion ? 0 : 6)
            .onAppear {
                guard !visible else { return }
                withAnimation(Motion.animation(.gentle, reduceMotion: reduceMotion).delay(reduceMotion ? 0 : delay)) {
                    visible = true
                }
            }
    }
}

extension View {
    func riseIn(delay: Double = 0) -> some View {
        modifier(RiseInModifier(delay: delay))
    }
}

/// Пружинящее нажатие для кастомных кнопок.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(SpringToken.quick.animation, value: configuration.isPressed)
    }
}
