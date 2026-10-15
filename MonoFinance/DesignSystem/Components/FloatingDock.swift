import SwiftUI

/// Плавающий док вместо стандартного таб-бара: четыре раздела и голосовая кнопка в центре — главный способ добавить операцию.
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
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Capsule(style: .continuous).fill(Color.mono.surface1.opacity(colorScheme == .dark ? 0.72 : 0.6)))
        }
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.mono.rimTop, Color.mono.rimBottom], startPoint: .top, endPoint: .bottom), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.12), radius: 24, x: 0, y: 12)
        .padding(.horizontal, 16)
    }

    private func tab(_ tab: AppTab) -> some View {
        let selected = selection == tab
        return Button {
            guard !selected else { return }
            Haptics.selection()
            withMonoAnimation(.quick) { selection = tab }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 18, weight: selected ? .semibold : .regular))
                    .symbolEffect(.bounce, value: selected)
                    .frame(height: 22)
                Text(tab.title)
                    .monoFont(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Color.mono.textPrimary : Color.mono.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if selected {
                    Capsule(style: .continuous)
                        .fill(Color.mono.surface3.opacity(0.9))
                        .matchedGeometryEffect(id: "dock-selection", in: namespace)
                }
            }
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
                    .fill(AngularGradient(colors: [Color.mono.electric, Color.mono.violet, Color.mono.cyan, Color.mono.electric], center: .center))
                    .frame(width: 58, height: 58)
                    .blur(radius: 10)
                    .opacity(0.6)
                Circle()
                    .fill(LinearGradient(colors: [Color.mono.electric, Color.mono.violet], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 54, height: 54)
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                Image(systemName: "mic.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 58)
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
