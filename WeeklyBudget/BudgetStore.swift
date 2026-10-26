import Foundation
import Observation
import SwiftUI

struct BudgetCategory: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var icon: String
    var budget: Double
    /// Unused money carried in from previous weeks.
    var rollover: Double = 0

    var available: Double { budget + rollover }

    static let icons = [
        "fork.knife", "cart", "ticket", "car", "house", "bolt", "cup.and.saucer", "bag",
        "tshirt", "gift", "airplane", "fuelpump", "heart", "pawprint", "dumbbell", "gamecontroller",
        "book", "phone", "creditcard", "tag",
    ]

    static let defaults = [
        BudgetCategory(name: "Food", icon: "fork.knife", budget: 100),
        BudgetCategory(name: "Groceries", icon: "cart", budget: 100),
        BudgetCategory(name: "Entertainment", icon: "ticket", budget: 50),
        BudgetCategory(name: "Uber / Lyft", icon: "car", budget: 50),
    ]
}

struct Expense: Codable, Identifiable {
    var id = UUID()
    var categoryID: UUID
    var amount: Double
    var note: String
    var date = Date()
}

/// A finished week, kept so past spending can be looked back on.
struct WeekRecord: Codable, Identifiable {
    var weekStart: Date
    /// Categories as they were that week, including that week's rollover.
    var categories: [BudgetCategory]
    var expenses: [Expense]

    var id: Date { weekStart }
    var totalAvailable: Double { categories.reduce(0) { $0 + $1.available } }
    var totalSpent: Double { expenses.reduce(0) { $0 + $1.amount } }
    func expenses(for c: BudgetCategory) -> [Expense] {
        expenses.filter { $0.categoryID == c.id }.sorted { $0.date > $1.date }
    }
    func spent(for c: BudgetCategory) -> Double { expenses(for: c).reduce(0) { $0 + $1.amount } }
}

private struct SavedState: Codable {
    var categories: [BudgetCategory]
    var weekStart: Date
    var expenses: [Expense]
    var hasSetBudgets: Bool
    /// Optional so saves from before history existed still load.
    var history: [WeekRecord]?
}

/// Format written by version 1.0, which had four fixed categories.
private struct LegacyState: Codable {
    struct LegacyExpense: Codable { var id: UUID; var category: String; var amount: Double; var note: String; var date: Date }
    var budgets: [String: Double]
    var weekStart: Date
    var expenses: [LegacyExpense]
    var hasSetBudgets: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // v1 encoded an enum-keyed dictionary as a flat [key, value, key, value] array.
        var arr = try c.nestedUnkeyedContainer(forKey: .budgets)
        var b: [String: Double] = [:]
        while !arr.isAtEnd { let k = try arr.decode(String.self); b[k] = try arr.decode(Double.self) }
        budgets = b
        weekStart = try c.decode(Date.self, forKey: .weekStart)
        expenses = try c.decode([LegacyExpense].self, forKey: .expenses)
        hasSetBudgets = try c.decode(Bool.self, forKey: .hasSetBudgets)
    }

    func migrated() -> SavedState {
        let keys = ["food", "groceries", "entertainment", "rides"]
        var cats = BudgetCategory.defaults
        var idFor: [String: UUID] = [:]
        for (i, k) in keys.enumerated() {
            if let b = budgets[k] { cats[i].budget = b }
            idFor[k] = cats[i].id
        }
        let exps = expenses.compactMap { e in
            idFor[e.category].map { Expense(id: e.id, categoryID: $0, amount: e.amount, note: e.note, date: e.date) }
        }
        return SavedState(categories: cats, weekStart: weekStart, expenses: exps, hasSetBudgets: hasSetBudgets)
    }
}

@Observable
final class BudgetStore {
    private(set) var categories: [BudgetCategory] { didSet { save() } }
    private(set) var expenses: [Expense] { didSet { save() } }
    private(set) var weekStart: Date { didSet { save() } }
    var hasSetBudgets: Bool { didSet { save() } }
    /// Past weeks, newest first.
    private(set) var history: [WeekRecord] { didSet { save() } }

    private static let fileURL = URL.documentsDirectory.appending(path: "budget-v2.json")
    private static let legacyURL = URL.documentsDirectory.appending(path: "budget.json")

    init() {
        let state: SavedState
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode(SavedState.self, from: data) {
            state = saved
        } else if let data = try? Data(contentsOf: Self.legacyURL),
                  let old = try? JSONDecoder().decode(LegacyState.self, from: data) {
            state = old.migrated()
        } else {
            state = SavedState(categories: BudgetCategory.defaults, weekStart: Self.currentWeekStart(), expenses: [], hasSetBudgets: false)
        }
        categories = state.categories
        expenses = state.expenses
        weekStart = state.weekStart
        hasSetBudgets = state.hasSetBudgets
        history = state.history ?? []
        resetIfNewWeek()
        save()
    }

    /// Monday 12:00 AM of the current week, local time.
    static func currentWeekStart(_ now: Date = .now) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: now)!.start
    }

    /// On a new week: the finished week is saved to history, unused money in each category
    /// rolls over, then spending clears. Overspending does not reduce next week.
    /// Weeks the app wasn't opened roll over in full.
    func resetIfNewWeek() {
        let current = Self.currentWeekStart()
        guard weekStart < current else { return }
        if !expenses.isEmpty {
            history.insert(WeekRecord(weekStart: weekStart, categories: categories, expenses: expenses), at: 0)
        }
        let weeks = max(1, Int((current.timeIntervalSince(weekStart) / (7 * 86_400)).rounded()))
        categories = categories.map { c in
            var c = c
            let unused = max(0, c.available - spent(for: c))
            c.rollover = unused + Double(weeks - 1) * c.budget
            return c
        }
        expenses = []
        weekStart = current
    }

    func category(_ id: UUID) -> BudgetCategory? { categories.first { $0.id == id } }
    func expenses(for c: BudgetCategory) -> [Expense] {
        expenses.filter { $0.categoryID == c.id }.sorted { $0.date > $1.date }
    }
    func spent(for c: BudgetCategory) -> Double { expenses(for: c).reduce(0) { $0 + $1.amount } }

    var totalAvailable: Double { categories.reduce(0) { $0 + $1.available } }
    var totalSpent: Double { expenses.reduce(0) { $0 + $1.amount } }

    func add(_ amount: Double, to id: UUID, note: String) {
        resetIfNewWeek()
        expenses.append(Expense(categoryID: id, amount: amount, note: note))
    }

    func update(_ e: Expense) {
        if let i = expenses.firstIndex(where: { $0.id == e.id }) { expenses[i] = e }
    }

    func delete(_ e: Expense) { expenses.removeAll { $0.id == e.id } }

    func upsert(_ c: BudgetCategory) {
        if let i = categories.firstIndex(where: { $0.id == c.id }) { categories[i] = c } else { categories.append(c) }
    }

    func deleteCategory(_ c: BudgetCategory) {
        categories.removeAll { $0.id == c.id }
        expenses.removeAll { $0.categoryID == c.id }
    }

    func moveCategories(from: IndexSet, to: Int) { categories.move(fromOffsets: from, toOffset: to) }

    private func save() {
        let state = SavedState(categories: categories, weekStart: weekStart, expenses: expenses,
                               hasSetBudgets: hasSetBudgets, history: history)
        try? JSONEncoder().encode(state).write(to: Self.fileURL, options: .atomic)
    }
}

extension Double {
    var money: String { formatted(.currency(code: "USD")) }
}

extension Date {
    /// "Oct 20 – Oct 26" for the week starting on this date.
    var weekRange: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: self)!
        let f = Date.FormatStyle().month(.abbreviated).day()
        return "\(formatted(f)) – \(end.formatted(f))"
    }
}
