import SwiftUI

/// Краткое уведомление (например, «Операция удалена · Вернуть»).
struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
    var symbol: String = "checkmark.circle.fill"
    var tint: Color = Color.mono.positive
    var actionTitle: String?
    var action: (() -> Void)?
}

@MainActor
@Observable
final class ToastCenter {
    private(set) var current: ToastMessage?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: ToastMessage, duration: Duration = .seconds(3.5)) {
        dismissTask?.cancel()
        withMonoAnimation(.standard) { current = message }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        withMonoAnimation(.standard) { current = nil }
    }
}

struct ToastOverlay: View {
    @Bindable var center: ToastCenter

    var body: some View {
        VStack {
            if let toast = center.current {
                HStack(spacing: 12) {
                    Image(systemName: toast.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(toast.tint)
                    Text(verbatim: toast.text)
                        .monoFont(.callout)
                        .foregroundStyle(Color.mono.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if let title = toast.actionTitle, let action = toast.action {
                        Button {
                            Haptics.tap()
                            action()
                            center.dismiss()
                        } label: {
                            Text(verbatim: title)
                                .monoFont(.headline)
                                .foregroundStyle(Color.mono.accentText)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Capsule(style: .continuous).fill(Color.mono.surface2))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.mono.strokeStrong, lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 10)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { center.dismiss() }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isStaticText)
            }
            Spacer()
        }
        .padding(.top, 8)
    }
}
