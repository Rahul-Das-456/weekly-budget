import SwiftUI

struct ContentView: View {
    @Environment(BudgetStore.self) private var store
    @State private var addingTo: UUID?
    @State private var showAdd = false
    @State private var showBudgets = false
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system
    /// Bumped to rebuild the title bar so it picks up a new theme's title style.
    @State private var titleBarGeneration = 0
    @State private var themeChanged = false

    private var weekRange: String { store.weekStart.weekRange }

    var body: some View {
        NavigationStack {
            List {
                if AppUpkeep.shared.expiresSoon || AppUpkeep.shared.newerVersion != nil {
                    Section { UpkeepBanner() }.themedRow()
                }
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("THIS WEEK \(theme.separator) \(weekRange)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text((store.totalAvailable - store.totalSpent).money)
                            .font(.system(size: 40, weight: .bold, design: theme.displayDesign))
                            .foregroundStyle(store.totalSpent > store.totalAvailable ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                        Text("left of \(store.totalAvailable.money) · \(store.totalSpent.money) spent")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                .themedRow()

                Section("Categories") {
                    ForEach(store.categories) { c in
                        NavigationLink {
                            CategoryDetailView(categoryID: c.id, onAdd: { addingTo = c.id; showAdd = true })
                        } label: {
                            CategoryRow(category: c)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Add") { addingTo = c.id; showAdd = true }.tint(theme.accent)
                        }
                    }
                    Button {
                        showBudgets = true
                    } label: {
                        Label("Add or edit categories", systemImage: "plus.circle")
                    }
                }
                .themedRow()

                Section {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label("Past weeks", systemImage: "clock.arrow.circlepath")
                    }
                }
                .themedRow()
            }
            .themedList()
            .navigationTitle("Budget")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showBudgets = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Settings")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    addingTo = nil
                    showAdd = true
                } label: {
                    Label("Add expense", systemImage: theme.addIcon)
                        .font(.headline)
                        .foregroundStyle(theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .disabled(store.categories.isEmpty)
            }
            .sheet(isPresented: $showAdd) {
                AddExpenseView(initial: addingTo ?? store.categories.first?.id)
            }
            .sheet(isPresented: $showBudgets, onDismiss: {
                if themeChanged {
                    themeChanged = false
                    titleBarGeneration += 1
                }
            }) {
                BudgetSettingsView()
            }
            .task {
                // Wait for the first frame so the sheet can present.
                try? await Task.sleep(for: .milliseconds(300))
                if !store.hasSetBudgets { showBudgets = true }
            }
        }
        .id(titleBarGeneration)
        .onChange(of: theme) { _, new in
            new.applyToNavigationBars()
            themeChanged = true
        }
    }
}

struct CategoryRow: View {
    @Environment(BudgetStore.self) private var store
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system
    let category: BudgetCategory

    var body: some View {
        let available = category.available
        let spent = store.spent(for: category)
        let left = available - spent
        let over = left < 0

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // The name shrinks a little before wrapping when it's long or the theme's font is wide.
                ThemedLabel(category.name, systemImage: category.icon).font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 8)
                Text("\(spent.money) / \(available.money)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    .fixedSize()
            }
            ProgressView(value: available > 0 ? min(spent / available, 1) : (spent > 0 ? 1 : 0))
                .tint(over ? .red : theme.accent)
            HStack {
                Text(over ? "\((-left).money) over" : "\(left.money) left")
                    .foregroundStyle(over ? .red : .secondary)
                Spacer()
                if category.rollover > 0 {
                    Text("+\(category.rollover.money) rolled over")
                        .foregroundStyle(theme.accent)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

struct CategoryDetailView: View {
    @Environment(BudgetStore.self) private var store
    let categoryID: UUID
    let onAdd: () -> Void
    @State private var editing: Expense?
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system

    var body: some View {
        if let category = store.category(categoryID) {
            List {
                Section {
                    CategoryRow(category: category)
                } footer: {
                    Text("\(category.budget.money) weekly budget + \(category.rollover.money) rolled over from past weeks.")
                }
                .themedRow()
                Section {
                    let items = store.expenses(for: category)
                    if items.isEmpty {
                        Text("No expenses yet this week.").foregroundStyle(.secondary)
                    }
                    ForEach(items) { e in
                        Button { editing = e } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(e.note.isEmpty ? category.name : e.note)
                                    Text(e.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(e.amount.money).monospacedDigit()
                            }
                            .foregroundStyle(.primary)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Edit") { editing = e }.tint(theme.accent)
                        }
                    }
                    .onDelete { idx in idx.map { items[$0] }.forEach(store.delete) }
                } header: {
                    Text("This week")
                } footer: {
                    if !store.expenses(for: category).isEmpty {
                        Text("Tap an expense to edit it. Swipe left to delete.")
                    }
                }
                .themedRow()
            }
            .themedList()
            .navigationTitle(category.name)
            .sheet(item: $editing) { e in
                AddExpenseView(editing: e)
            }
            .toolbar {
                Button(action: onAdd) { Image(systemName: "plus") }
                    .accessibilityLabel("Add expense")
            }
        } else {
            ContentUnavailableView("Category deleted", systemImage: "trash")
        }
    }
}

struct HistoryView: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        List {
            if store.history.isEmpty {
                ContentUnavailableView("No past weeks yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("When a new week starts on Monday, last week's expenses are saved here."))
                    .themedRow()
            }
            ForEach(store.history) { week in
                NavigationLink {
                    PastWeekView(week: week)
                } label: {
                    let over = week.totalSpent > week.totalAvailable
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(week.weekStart.weekRange).font(.headline)
                            Text("\(week.expenses.count) expense\(week.expenses.count == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(week.totalSpent.money).monospacedDigit()
                            Text("of \(week.totalAvailable.money)")
                                .font(.caption).foregroundStyle(over ? .red : .secondary)
                        }
                    }
                }
            }
            .themedRow()
        }
        .themedList()
        .navigationTitle("Past weeks")
    }
}

struct PastWeekView: View {
    let week: WeekRecord
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(week.totalSpent.money)
                        .font(.system(size: 34, weight: .bold, design: theme.displayDesign))
                        .foregroundStyle(week.totalSpent > week.totalAvailable ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                    Text("spent of \(week.totalAvailable.money)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            .themedRow()
            ForEach(week.categories) { c in
                let items = week.expenses(for: c)
                let spent = week.spent(for: c)
                Section {
                    ForEach(items) { e in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(e.note.isEmpty ? c.name : e.note)
                                Text(e.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(e.amount.money).monospacedDigit()
                        }
                    }
                    if items.isEmpty {
                        Text("No expenses").foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        ThemedLabel(c.name, systemImage: c.icon)
                        Spacer()
                        Text("\(spent.money) / \(c.available.money)")
                            .monospacedDigit()
                            .foregroundStyle(spent > c.available ? .red : .secondary)
                    }
                }
                .themedRow()
            }
        }
        .themedList()
        .navigationTitle(week.weekStart.weekRange)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AddExpenseView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var categoryID: UUID?
    @State private var amount: Double?
    @State private var note = ""
    @State private var confirmDelete = false
    @FocusState private var amountFocused: Bool
    /// The expense being edited, or nil when adding a new one.
    private let original: Expense?

    init(initial: UUID?) {
        _categoryID = State(initialValue: initial)
        original = nil
    }

    init(editing e: Expense) {
        _categoryID = State(initialValue: e.categoryID)
        _amount = State(initialValue: e.amount)
        _note = State(initialValue: e.note)
        original = e
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Category", selection: $categoryID) {
                        ForEach(store.categories) { Label($0.name, systemImage: $0.icon).tag(Optional($0.id)) }
                    }
                    TextField("Amount", value: $amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                    TextField("Note (optional)", text: $note)
                }
                .themedRow()
                if original != nil {
                    Section {
                        Button("Delete expense", role: .destructive) { confirmDelete = true }
                    }
                    .themedRow()
                }
            }
            .themedList()
            .navigationTitle(original == nil ? "Add expense" : "Edit expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(original == nil ? "Add" : "Save") {
                        if let amount, amount > 0, let categoryID {
                            let trimmed = note.trimmingCharacters(in: .whitespaces)
                            if var e = original {
                                e.amount = amount
                                e.categoryID = categoryID
                                e.note = trimmed
                                store.update(e)
                            } else {
                                store.add(amount, to: categoryID, note: trimmed)
                            }
                        }
                        dismiss()
                    }
                    .disabled((amount ?? 0) <= 0 || categoryID == nil)
                }
            }
            .confirmationDialog("Delete this expense?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let original { store.delete(original) }
                    dismiss()
                }
            }
            .onAppear { if original == nil { amountFocused = true } }
        }
        .themed()
        .presentationDetents([.medium])
    }
}

struct BudgetSettingsView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editing: BudgetCategory?
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.categories) { c in
                        Button { editing = c } label: {
                            HStack {
                                ThemedLabel(c.name, systemImage: c.icon).foregroundStyle(.primary)
                                Spacer()
                                Text(c.budget.money + "/wk").foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                    .onDelete { idx in idx.map { store.categories[$0] }.forEach(store.deleteCategory) }
                    .onMove(perform: store.moveCategories)

                    Button {
                        editing = BudgetCategory(name: "", icon: "tag", budget: 50)
                    } label: {
                        Label("Add category", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Categories")
                } footer: {
                    Text("Every Monday, spending resets to $0 and any unused money in a category rolls over to the next week. Swipe left to delete a category.")
                }
                .themedRow()

                Section("Theme") {
                    Picker("Theme", selection: $theme) {
                        ForEach(AppTheme.allCases) { Label($0.name, systemImage: $0.icon).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                .themedRow()

                UpkeepSettingsSection().themedRow()
            }
            .themedList()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.hasSetBudgets = true
                        dismiss()
                    }
                }
            }
            .sheet(item: $editing) { c in
                CategoryEditView(category: c, isNew: store.category(c.id) == nil)
            }
        }
        .themed()
    }
}

struct CategoryEditView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var category: BudgetCategory
    let isNew: Bool
    @State private var confirmDelete = false
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system

    private var trimmedName: String { category.name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Gym, Coffee)", text: $category.name)
                    HStack {
                        Text("Weekly budget")
                        Spacer()
                        TextField("0", value: $category.budget, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                    }
                }
                .themedRow()
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(BudgetCategory.icons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(category.icon == icon ? theme.accent.opacity(0.2) : .clear,
                                            in: RoundedRectangle(cornerRadius: 10))
                                .onTapGesture { category.icon = icon }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel(icon)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .themedRow()
                if !isNew {
                    Section {
                        LabeledContent("Rolled over", value: category.rollover.money)
                        if category.rollover > 0 {
                            Button("Clear rollover") { category.rollover = 0 }
                        }
                    } footer: {
                        Text("Unused money from past weeks. It's added on top of the weekly budget.")
                    }
                    .themedRow()
                    Section {
                        Button("Delete category", role: .destructive) { confirmDelete = true }
                    }
                    .themedRow()
                }
            }
            .themedList()
            .navigationTitle(isNew ? "New category" : "Edit category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        category.name = trimmedName
                        category.budget = max(0, category.budget)
                        store.upsert(category)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
            .confirmationDialog("Delete \(category.name)? Its expenses this week will be deleted too.",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.deleteCategory(category)
                    dismiss()
                }
            }
        }
        .themed()
    }
}

#Preview {
    ContentView().environment(BudgetStore())
}
