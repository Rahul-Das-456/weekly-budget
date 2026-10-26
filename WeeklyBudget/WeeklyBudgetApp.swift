import SwiftUI

@main
struct WeeklyBudgetApp: App {
    @State private var store = BudgetStore()
    @Environment(\.scenePhase) private var scenePhase

    init() { AppTheme.saved.applyToNavigationBars() }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .themed()
                .task { await AppUpkeep.shared.refresh() }   // first launch; later ones come from scenePhase
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.resetIfNewWeek()
                Task { await AppUpkeep.shared.refresh() }   // expiry alerts + GitHub check
            }
        }
    }
}
