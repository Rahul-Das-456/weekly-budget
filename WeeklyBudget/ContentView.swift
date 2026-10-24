import SwiftUI

struct ContentView: View {
    @Environment(BudgetStore.self) private var store
    @State private var addingTo: UUID?
    @State private var showAdd = false
    @State private var showBudgets = false

    private var weekRange: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: store.weekStart)!
        let f = Date.FormatStyle().month(.abbreviated).day()
        return "\(store.weekStart.formatted(f)) – \(end.formatted(f))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("THIS WEEK · \(weekRange)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text((store.totalAvailable - store.totalSpent).money)
                            .font(.system(size: 40, weight: .bold, design: .serif))
                            .foregroundStyle(store.totalSpent > store.totalAvailable ? .red : .primary)
                        Text("left of \(store.totalAvailable.money) · \(store.totalSpent.money) spent")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("Categories") {
                    ForEach(store.categories) { c in
                        NavigationLink {
                            CategoryDetailView(categoryID: c.id, onAdd: { addingTo = c.id; showAdd = true })
                        } label: {
                            CategoryRow(category: c)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Add") { addingTo = c.id; showAdd = true }.tint(.accentColor)
                        }
                    }
                    Button {
                        showBudgets = true
                    } label: {
                        Label("Add or edit categories", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("Budget")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showBudgets = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Edit budgets and categories")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    addingTo = nil
                    showAdd = true
                } label: {
                    Label("Add expense", systemImage: "plus")
                        .font(.headline)
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
            .sheet(isPresented: $showBudgets) {
                BudgetSettingsView()
            }
            .task {
                // Wait for the first frame so the sheet can present.
                try? await Task.sleep(for: .milliseconds(300))
                if !store.hasSetBudgets { showBudgets = true }
            }
        }
    }
}

struct CategoryRow: View {
    @Environment(BudgetStore.self) private var store
    let category: BudgetCategory

    var body: some View {
        let available = category.available
        let spent = store.spent(for: category)
        let left = available - spent
        let over = left < 0

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(category.name, systemImage: category.icon).font(.headline)
                Spacer()
                Text("\(spent.money) / \(available.money)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: available > 0 ? min(spent / available, 1) : (spent > 0 ? 1 : 0))
                .tint(over ? .red : .accentColor)
            HStack {
                Text(over ? "\((-left).money) over" : "\(left.money) left")
                    .foregroundStyle(over ? .red : .secondary)
                Spacer()
                if category.rollover > 0 {
                    Text("+\(category.rollover.money) rolled over")
                        .foregroundStyle(Color.accentColor)
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

    var body: some View {
        if let category = store.category(categoryID) {
            List {
                Section {
                    CategoryRow(category: category)
                } footer: {
                    Text("\(category.budget.money) weekly budget + \(category.rollover.money) rolled over from past weeks.")
                }
                Section("This week") {
                    let items = store.expenses(for: category)
                    if items.isEmpty {
                        Text("No expenses yet this week.").foregroundStyle(.secondary)
                    }
                    ForEach(items) { e in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(e.note.isEmpty ? category.name : e.note)
                                Text(e.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(e.amount.money).monospacedDigit()
                        }
                    }
                    .onDelete { idx in idx.map { items[$0] }.forEach(store.delete) }
                }
            }
            .navigationTitle(category.name)
            .toolbar {
                Button(action: onAdd) { Image(systemName: "plus") }
                    .accessibilityLabel("Add expense")
            }
        } else {
            ContentUnavailableView("Category deleted", systemImage: "trash")
        }
    }
}

struct AddExpenseView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var categoryID: UUID?
    @State private var amount: Double?
    @State private var note = ""
    @FocusState private var amountFocused: Bool

    init(initial: UUID?) { _categoryID = State(initialValue: initial) }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Category", selection: $categoryID) {
                    ForEach(store.categories) { Label($0.name, systemImage: $0.icon).tag(Optional($0.id)) }
                }
                TextField("Amount", value: $amount, format: .currency(code: "USD"))
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                TextField("Note (optional)", text: $note)
            }
            .navigationTitle("Add expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let amount, amount > 0, let categoryID {
                            store.add(amount, to: categoryID, note: note.trimmingCharacters(in: .whitespaces))
                        }
                        dismiss()
                    }
                    .disabled((amount ?? 0) <= 0 || categoryID == nil)
                }
            }
            .onAppear { amountFocused = true }
        }
        .presentationDetents([.medium])
    }
}

struct BudgetSettingsView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editing: BudgetCategory?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.categories) { c in
                        Button { editing = c } label: {
                            HStack {
                                Label(c.name, systemImage: c.icon).foregroundStyle(.primary)
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
                } footer: {
                    Text("Every Monday, spending resets to $0 and any unused money in a category rolls over to the next week. Swipe left to delete a category.")
                }
            }
            .navigationTitle("Categories")
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
    }
}

struct CategoryEditView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var category: BudgetCategory
    let isNew: Bool
    @State private var confirmDelete = false

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
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(BudgetCategory.icons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(category.icon == icon ? Color.accentColor.opacity(0.2) : .clear,
                                            in: RoundedRectangle(cornerRadius: 10))
                                .onTapGesture { category.icon = icon }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel(icon)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if !isNew {
                    Section {
                        LabeledContent("Rolled over", value: category.rollover.money)
                        if category.rollover > 0 {
                            Button("Clear rollover") { category.rollover = 0 }
                        }
                    } footer: {
                        Text("Unused money from past weeks. It's added on top of the weekly budget.")
                    }
                    Section {
                        Button("Delete category", role: .destructive) { confirmDelete = true }
                    }
                }
            }
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
    }
}

#Preview {
    ContentView().environment(BudgetStore())
}
