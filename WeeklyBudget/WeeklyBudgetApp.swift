import SwiftUI

@main
struct WeeklyBudgetApp: App {
    @State private var store = BudgetStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.resetIfNewWeek() }
        }
    }
}
