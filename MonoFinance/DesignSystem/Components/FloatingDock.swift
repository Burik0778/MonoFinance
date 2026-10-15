import SwiftUI

/// Строка ввода внизу главного экрана — единственный постоянный элемент управления.
/// Слева — ручной ввод, справа — микрофон. Долгое нажатие открывает доход, перевод и импорт.
struct CommandBar: View {
    let onVoice: () -> Void
    let onManual: () -> Void
    let onIncome: () -> Void
    let onTransfer: () -> Void
    let onImport: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            Button {
                Haptics.tap()
                onManual()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Новая операция")
                        .monoFont(.headline)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.mono.textPrimary)
                .padding(.leading, 22)
                .frame(height: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.98))
            .contextMenu {
                Button(action: onManual) { Label("Расход", systemImage: "arrow.up.right") }
                Button(action: onIncome) { Label("Доход", systemImage: "arrow.down.left") }
                Button(action: onTransfer) { Label("Перевод между счетами", systemImage: "arrow.left.arrow.right") }
                Button(action: onImport) { Label("Импорт выписки", systemImage: "tray.and.arrow.down") }
            }
            .accessibilityLabel(Text("Новая операция"))
            .accessibilityHint(Text("Удерживайте, чтобы выбрать доход, перевод или импорт"))

            Button {
                Haptics.rigid()
                onVoice()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.mono.onAccent)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Color.mono.accent))
                    .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .padding(.trailing, 5)
            .accessibilityLabel(Text("Голосовой ввод операции"))
        }
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Capsule(style: .continuous).fill(Color.mono.surface1.opacity(colorScheme == .dark ? 0.9 : 0.8)))
        }
        .overlay(Capsule(style: .continuous).strokeBorder(Color.mono.strokeStrong, lineWidth: 1))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.55 : 0.12), radius: 24, x: 0, y: 12)
        .padding(.horizontal, 20)
    }
}
