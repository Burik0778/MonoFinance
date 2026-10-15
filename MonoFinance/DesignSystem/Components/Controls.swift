import SwiftUI
import UIKit
import MonoCore

/// Значок категории: скруглённый квадрат с тонированной заливкой.
struct CategoryGlyph: View {
    let icon: String
    let color: Color
    var size: CGFloat = 40

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
        Image(systemName: icon)
            .font(.system(size: size * 0.42, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(shape.fill(color.opacity(0.16)))
            .overlay(shape.strokeBorder(color.opacity(0.28), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

extension CategoryGlyph {
    init(category: FinanceCategory?, kind: TransactionKind, size: CGFloat = 40) {
        if let category {
            self.init(icon: category.icon, color: category.color.color, size: size)
        } else {
            self.init(icon: kind.symbol, color: kind.tint, size: size)
        }
    }
}

/// Переключатель-«пилюли» со скользящей подложкой.
struct SegmentedPills<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    var stretch = false

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    guard !selected else { return }
                    Haptics.selection()
                    withMonoAnimation(.quick) { selection = option }
                } label: {
                    Text(verbatim: title(option))
                        .monoFont(.subhead)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: stretch ? .infinity : nil)
                        .foregroundStyle(selected ? Color.mono.textPrimary : Color.mono.textSecondary)
                        .background {
                            if selected {
                                Capsule(style: .continuous)
                                    .fill(Color.mono.surface3)
                                    .overlay(Capsule(style: .continuous).strokeBorder(Color.mono.strokeStrong, lineWidth: 1))
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule(style: .continuous).fill(Color.mono.surface1))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.mono.strokeSubtle, lineWidth: 1))
    }
}

/// Полоса прогресса (бюджеты, цели).
struct ProgressTrack: View {
    let progress: Double
    var tint: Color = Color.mono.electric
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.mono.surface3)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, proxy.size.width * clamped))
                    .opacity(clamped > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: "\(Int((progress * 100).rounded()))%"))
    }
}

/// Кольцо прогресса.
struct ProgressRing: View {
    let progress: Double
    var tint: Color = Color.mono.electric
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(Color.mono.surface3, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.6), tint], center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: "\(Int((progress * 100).rounded()))%"))
    }
}

/// Перенос элементов по строкам (чипы, теги).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Поле ввода в стиле MONO.
struct MonoTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var systemImage: String?
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.mono.textTertiary)
                    .frame(width: 20)
            }
            TextField(title, text: $text)
                .monoFont(.body)
                .foregroundStyle(Color.mono.textPrimary)
                .keyboardType(keyboard)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.surface3))
        .overlay(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).strokeBorder(Color.mono.strokeSubtle, lineWidth: 1))
    }
}

/// Строка-ссылка в списках настроек и форм.
struct FormRow<Trailing: View>: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    var subtitle: Text?
    let trailing: Trailing

    init(icon: String, tint: Color, title: LocalizedStringKey, subtitle: Text? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            CategoryGlyph(icon: icon, color: tint, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .monoFont(.body)
                    .foregroundStyle(Color.mono.textPrimary)
                if let subtitle {
                    subtitle
                        .monoFont(.footnote)
                        .foregroundStyle(Color.mono.textSecondary)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            trailing
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

extension FormRow where Trailing == EmptyView {
    init(icon: String, tint: Color, title: LocalizedStringKey, subtitle: Text? = nil) {
        self.init(icon: icon, tint: tint, title: title, subtitle: subtitle) { EmptyView() }
    }
}
