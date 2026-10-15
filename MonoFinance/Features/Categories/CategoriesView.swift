import SwiftUI
import MonoCore

/// Категории расходов и доходов: свои и встроенные, архив, обязательные траты.
struct CategoriesView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.appLanguage) private var language
    @State private var kind: CategoryKind = .expense

    var body: some View {
        let all = store.categories.filter { $0.kind == kind }.sorted { $0.sortOrder < $1.sortOrder }
        let active = all.filter { !$0.isArchived }
        let archived = all.filter(\.isArchived)
        let usage = usageCounts()

        List {
            Section {
                SegmentedPills(options: [CategoryKind.expense, .income], selection: $kind,
                               title: { $0 == .expense ? Phrase(ru: "Расходы", uz: "Xarajatlar", en: "Expenses")(language) : Phrase(ru: "Доходы", uz: "Daromadlar", en: "Income")(language) },
                               stretch: true)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            Section {
                ForEach(active) { category in
                    row(category, count: usage[category.id] ?? 0)
                }
            } footer: {
                if kind == .expense {
                    Text("Значок замка — обязательная трата: учитывается в доле обязательных расходов в аналитике.")
                        .monoFont(.caption)
                }
            }
            if !archived.isEmpty {
                Section {
                    ForEach(archived) { category in
                        row(category, count: usage[category.id] ?? 0)
                    }
                } header: {
                    Kicker("Архив")
                }
            }
            Section {
                Button {
                    router.open(.merchantRules)
                } label: {
                    FormRow(icon: "brain.head.profile", tint: Color.mono.accent, title: "Выученные правила",
                            subtitle: Text("Продавец → категория: \(store.merchantRules.count)")) {
                        Image(systemName: "chevron.right").foregroundStyle(Color.mono.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.mono.surface1)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.mono.background.ignoresSafeArea())
        .navigationTitle(Text("Категории"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.present(.category(nil, kind))
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("Новая категория"))
            }
        }
    }

    private func row(_ category: FinanceCategory, count: Int) -> some View {
        Button {
            router.present(.category(category, category.kind))
        } label: {
            HStack(spacing: 12) {
                CategoryGlyph(icon: category.icon, color: category.color.color, size: 38, tinted: true)
                    .opacity(category.isArchived ? 0.5 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(verbatim: category.name)
                            .monoFont(.body)
                            .foregroundStyle(category.isArchived ? Color.mono.textTertiary : Color.mono.textPrimary)
                        if category.isMandatory {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.mono.accentText)
                                .accessibilityLabel(Text("Обязательная"))
                        }
                    }
                    Text(verbatim: countText(count))
                        .monoFont(.caption)
                        .foregroundStyle(Color.mono.textTertiary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.mono.surface1)
        .swipeActions(edge: .trailing) {
            Button(category.isArchived ? "Вернуть" : "В архив", systemImage: category.isArchived ? "tray.and.arrow.up" : "archivebox") {
                do {
                    try store.setArchived(category, archived: !category.isArchived)
                    Haptics.selection()
                } catch {
                    toasts.show(ToastMessage(text: AppError(error).message, symbol: "xmark.octagon.fill", tint: Color.mono.negative))
                }
            }
            .tint(Color.mono.neutral)
        }
    }

    private func usageCounts() -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for transaction in store.transactions {
            if let id = transaction.categoryID { counts[id, default: 0] += 1 }
        }
        return counts
    }

    private func countText(_ count: Int) -> String {
        switch language {
        case .ru:
            let mod10 = count % 10, mod100 = count % 100
            let word = mod10 == 1 && mod100 != 11 ? "операция" : (2...4).contains(mod10) && !(12...14).contains(mod100) ? "операции" : "операций"
            return "\(count) \(word)"
        case .uz: return "\(count) ta amal"
        case .en: return count == 1 ? "1 transaction" : "\(count) transactions"
        }
    }
}

/// Создание и изменение категории. Удаление — только без операций; иначе перенос или архив.
struct CategoryEditorView: View {
    let category: FinanceCategory?
    let kind: CategoryKind

    @Environment(FinanceStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var icon = "tag.fill"
    @State private var color: CategoryColor = .electric
    @State private var mandatory = false
    @State private var reassignTarget: UUID?
    @State private var error: String?
    @State private var confirmsDelete = false
    @State private var loaded = false

    static let symbols = [
        "cart.fill", "basket.fill", "fork.knife", "cup.and.saucer.fill", "takeoutbag.and.cup.and.straw.fill", "car.fill", "fuelpump.fill",
        "bus.fill", "tram.fill", "airplane", "house.fill", "bolt.fill", "drop.fill", "flame.fill", "wifi", "iphone", "tv.fill",
        "gamecontroller.fill", "film.fill", "music.note", "book.fill", "graduationcap.fill", "heart.fill", "cross.case.fill", "pills.fill",
        "figure.run", "dumbbell.fill", "scissors", "tshirt.fill", "bag.fill", "gift.fill", "pawprint.fill", "figure.2.and.child.holdinghands",
        "briefcase.fill", "banknote.fill", "creditcard.fill", "building.columns.fill", "chart.line.uptrend.xyaxis", "percent",
        "wrench.and.screwdriver.fill", "hammer.fill", "leaf.fill", "sparkles", "star.fill", "tag.fill"
    ]

    private var isNew: Bool { category == nil }
    private var usageCount: Int {
        guard let category else { return 0 }
        return store.transactions.filter { $0.categoryID == category.id }.count
    }

    var body: some View {
        EditorScaffold(title: isNew ? "Новая категория" : "Категория", 
                       canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty, error: error, onSave: save) {
            HStack(spacing: 14) {
                CategoryGlyph(icon: icon, color: color.color, size: 56, tinted: true)
                MonoTextField(title: "Название", text: $name)
            }
            FormSection(title: "Значок") {
                SymbolPicker(selection: $icon, symbols: Self.symbols, tint: color.color)
            }
            FormSection(title: "Цвет") {
                ColorSwatchPicker(selection: $color)
            }
            if kind == .expense {
                ToggleRow(title: "Обязательная трата", subtitle: "Жильё, связь, кредиты, налоги — то, без чего не обойтись.", isOn: $mandatory, tint: Color.mono.accent)
            }
            if let category, !isNew {
                if category.systemKey != nil {
                    Text("Встроенная категория: её можно переименовать или убрать в архив.")
                        .monoFont(.caption)
                        .foregroundStyle(Color.mono.textTertiary)
                }
                if usageCount > 0 {
                    FormSection(title: "Перенести операции", footer: "Все \(usageCount) операции этой категории перейдут в выбранную. Это можно сделать перед удалением.") {
                        VStack(spacing: 10) {
                            Menu {
                                ForEach(store.activeCategories.filter { $0.kind == kind && $0.id != category.id }) { option in
                                    Button {
                                        reassignTarget = option.id
                                    } label: {
                                        Label(option.name, systemImage: option.icon)
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(verbatim: reassignTarget.flatMap { store.categoryMap[$0]?.name } ?? String(localized: "Выберите категорию"))
                                        .monoFont(.body)
                                        .foregroundStyle(Color.mono.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .foregroundStyle(Color.mono.textTertiary)
                                }
                                .padding(.horizontal, 14)
                                .frame(minHeight: 50)
                                .background(RoundedRectangle(cornerRadius: MonoTokens.Radius.md, style: .continuous).fill(Color.mono.surface2))
                            }
                            Button("Перенести") { reassign(category) }
                                .buttonStyle(SecondaryButtonStyle(tint: Color.mono.accent))
                                .disabled(reassignTarget == nil)
                        }
                    }
                }
                Button(category.isArchived ? "Вернуть из архива" : "Убрать в архив") {
                    try? store.setArchived(category, archived: !category.isArchived)
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
                if usageCount == 0 {
                    Button("Удалить категорию", role: .destructive) { confirmsDelete = true }
                        .buttonStyle(SecondaryButtonStyle(tint: Color.mono.negative))
                }
            }
        }
        .onAppear(perform: load)
        .confirmationDialog("Удалить категорию?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                guard let category else { return }
                do {
                    try store.deleteCategory(category)
                    dismiss()
                } catch {
                    self.error = AppError(error).message
                }
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let category else {
            color = kind == .income ? .emerald : .electric
            icon = kind == .income ? "banknote.fill" : "tag.fill"
            return
        }
        name = category.name
        icon = category.icon
        color = category.color
        mandatory = category.isMandatory
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let duplicate = store.categories.contains {
            $0.kind == kind && $0.id != category?.id && TextNormalizer.fold($0.name) == TextNormalizer.fold(trimmed)
        }
        if duplicate {
            error = String(localized: "Категория с таким названием уже есть.")
            return
        }
        var value = category ?? FinanceCategory(name: trimmed, kind: kind, icon: icon, color: color,
                                                sortOrder: (store.categories.map(\.sortOrder).max() ?? 0) + 1)
        value.name = trimmed
        value.icon = icon
        value.color = color
        value.isMandatory = kind == .expense && mandatory
        do {
            try store.saveCategory(value)
            Haptics.success()
            dismiss()
        } catch {
            self.error = AppError(error).message
        }
    }

    private func reassign(_ category: FinanceCategory) {
        guard let targetID = reassignTarget, let target = store.categoryMap[targetID] else { return }
        do {
            try store.reassign(from: category, to: target)
            Haptics.success()
            toasts.show(ToastMessage(text: String(localized: "Операции перенесены в «\(target.name)»"), symbol: "arrow.right.circle.fill"))
        } catch {
            self.error = AppError(error).message
        }
    }
}

/// Выученные правила категоризации: продавец → категория. Можно удалить ошибочное правило.
struct MerchantRulesView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        List {
            if store.merchantRules.isEmpty {
                EmptyStateView(symbol: "brain.head.profile", title: "Правил пока нет",
                               message: "Когда вы исправляете категорию операции, MONO запоминает выбор для этого продавца и дальше предлагает его сам.")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(store.merchantRules.sorted { $0.hits > $1.hits }) { rule in
                        let category = store.categoryMap[rule.categoryID]
                        HStack(spacing: 12) {
                            CategoryGlyph(category: category, kind: .expense, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: rule.key)
                                    .monoFont(.body)
                                    .foregroundStyle(Color.mono.textPrimary)
                                Text(verbatim: "→ \(category?.name ?? "—")")
                                    .monoFont(.caption)
                                    .foregroundStyle(Color.mono.textSecondary)
                            }
                            Spacer()
                            Text(verbatim: "×\(rule.hits)")
                                .monoFont(.caption, digits: true)
                                .foregroundStyle(Color.mono.textTertiary)
                        }
                        .listRowBackground(Color.mono.surface1)
                        .swipeActions {
                            Button("Забыть", systemImage: "trash", role: .destructive) {
                                do {
                                    try store.forgetRule(rule)
                                } catch {
                                    toasts.show(ToastMessage(text: AppError(error).message, symbol: "xmark.octagon.fill", tint: Color.mono.negative))
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Правила хранятся только на этом устройстве и имеют приоритет над встроенным справочником продавцов.")
                        .monoFont(.caption)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.mono.background.ignoresSafeArea())
        .navigationTitle(Text("Выученные правила"))
    }
}
