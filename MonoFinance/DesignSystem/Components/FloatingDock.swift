import SwiftUI

/// Плавающий док вместо стандартного таб-бара: четыре раздела и голосовая кнопка в центре — главный способ добавить операцию.
/// Выбор раздела — акцентный значок и точка под ним; голосовая кнопка — сплошной акцент без свечений.
/// Долгое нажатие на микрофон открывает ручной ввод и перевод.
struct FloatingDock: View {
    @Binding var selection: AppTab
    let onVoice: () -> Void
    let onManualEntry: () -> Void
    let onTransfer: () -> Void

    @Namespace private var namespace
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            tab(.overview)
            tab(.transactions)
            voiceButton
            tab(.analytics)
            tab(.plans)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.mono.surface1.opacity(colorScheme == .dark ? 0.86 : 0.75)))
        }
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.mono.strokeStrong, lineWidth: 1))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.12), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 16)
    }

    private func tab(_ tab: AppTab) -> some View {
        let selected = selection == tab
        return Button {
            guard !selected else { return }
            Haptics.selection()
            withMonoAnimation(.quick) { selection = tab }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 18, weight: selected ? .semibold : .regular))
                    .symbolEffect(.bounce, value: selected)
                    .frame(height: 22)
                Text(tab.title)
                    .monoFont(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                ZStack {
                    if selected {
                        Capsule()
                            .fill(Color.mono.accent)
                            .matchedGeometryEffect(id: "dock-selection", in: namespace)
                    }
                }
                .frame(width: 16, height: 3)
            }
            .foregroundStyle(selected ? Color.mono.textPrimary : Color.mono.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tab.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var voiceButton: some View {
        Button(action: onVoice) {
            ZStack {
                Circle()
                    .fill(Color.mono.accent)
                    .frame(width: 54, height: 54)
                    .overlay(Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
                Image(systemName: "mic.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.mono.onAccent)
            }
            .frame(width: 66, height: 58)
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .contextMenu {
            Button(action: onVoice) { Label("Голосовой ввод", systemImage: "mic.fill") }
            Button(action: onManualEntry) { Label("Ввести вручную", systemImage: "square.and.pencil") }
            Button(action: onTransfer) { Label("Перевод между счетами", systemImage: "arrow.left.arrow.right") }
        }
        .accessibilityLabel(Text("Голосовой ввод операции"))
        .accessibilityHint(Text("Удерживайте для ручного ввода"))
    }
}
