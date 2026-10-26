# Weekly Budget app: how it works

SwiftUI iPhone app, iOS 17+, no dependencies, no server. Display name "Budget", bundle ID `com.rahuldas.weeklybudget`.

- Project: this repo (https://github.com/Rahul-Das-456/weekly-budget). Rahul's copy is `~/WeeklyBudget`.
- GitHub (public): https://github.com/Rahul-Das-456/weekly-budget. Rahul's girlfriend uses this repo, so keep the README accurate.
- The Xcode project is generated from `project.yml` with `xcodegen generate`. Edit `project.yml`, never the `.pbxproj`.
- Version: `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`. History: 1.0 (build 1) had four fixed categories. 1.1 (build 2) added rollover and custom categories. 1.2 (build 3) added expense editing, past-week history and themes.

## Files

| File | What's in it |
|---|---|
| `WeeklyBudget/WeeklyBudgetApp.swift` | App entry point. Calls `store.resetIfNewWeek()` every time the app comes to the foreground. |
| `WeeklyBudget/BudgetStore.swift` | `BudgetCategory`, `Expense`, `SavedState`, `LegacyState` (1.0 migration), and `BudgetStore` (`@Observable`; saves JSON on every change). Also the icon list and the four default categories. |
| `WeeklyBudget/Theme.swift` | `AppTheme` (Match phone, Light, Dark, Pink, Hacker), saved choice, `.themed()` modifier and navigation bar colors (1.2). |
| `WeeklyBudget/ContentView.swift` | Every screen (1.2 adds editing an expense and Past weeks): `ContentView` (summary + category list + "Add expense" button), `CategoryRow`, `CategoryDetailView` (expense list, swipe to delete), `AddExpenseView` (medium sheet), `BudgetSettingsView` (list, add, reorder, delete), `CategoryEditView` (name, budget, icon grid, clear rollover, delete). |
| `WeeklyBudget/Assets.xcassets` | App icon (1024 px navy square with a gold ring) and AccentColor (navy #1a3a5c in light mode, gold #c4a472 in dark mode). |
| `WeeklyBudget.ipa` | Unsigned Release build, kept in the repo so people can install it with AltStore. Rebuild it with `scripts/build_ipa.sh` whenever the code changes. |

## Rules (keep these when changing anything)

- **Week** = Monday 12:00 AM to Sunday, local time (`BudgetStore.currentWeekStart`, gregorian, `firstWeekday = 2`).
- **New week** (`resetIfNewWeek`): for each category, `rollover = max(0, budget + rollover − spent)`, plus a full `budget` for every extra week the app wasn't opened. Then clear all expenses. Overspending never reduces next week's budget.
- **Available this week** = `budget + rollover`. The totals and progress bars use available, not budget.
- **History (1.2)**: before the reset, a week with expenses is saved as a `WeekRecord` (categories as they were, including rollover, plus expenses), newest first.
- Deleting a category also deletes its expenses. "Clear rollover" sets rollover to 0.
- First launch (`hasSetBudgets == false`) opens the categories sheet after 300 ms. `.onAppear` was too early for the sheet to show.

## Save file

`Documents/budget-v2.json` (JSONEncoder defaults: dates are seconds since 2001-01-01 UTC):

```json
{"categories":[{"id":"UUID","name":"Food","icon":"fork.knife","budget":100,"rollover":70}],
 "weekStart":814078800, "expenses":[{"id":"UUID","categoryID":"UUID","amount":12.5,"note":"","date":814100000}],
 "hasSetBudgets":true, "history":[ {"weekStart":..., "categories":[...], "expenses":[...]} ]}
```

The 1.0 format (`Documents/budget.json`, with enum keys `food/groceries/entertainment/rides` and `budgets` as a flat `[key, value, ...]` array) is read once by `LegacyState` and migrated. **If you ever change the save format, keep reading the old file**, because people already have data on their phones. Add a new decoder and a new file name, as 1.1 did. AltStore updates keep the app's Documents folder.

## Testing

`scripts/test_sim.sh <scenario> <png>` builds, seeds data, launches in the simulator, screenshots, and prints the saved categories. Scenarios: `fresh`, `thisweek`, `lastweek`, `legacy`, `keep`. Expected results:
- `fresh`: the "Categories" sheet is open, with Food 100, Groceries 100, Entertainment 50 and Uber / Lyft 50.
- `lastweek` and `legacy`: Food rollover 70, Groceries 100, Entertainment 50, Uber / Lyft 0. Expenses are cleared and the total is $520.
- `thisweek`: Food is red ($20 over), Groceries shows "+$40.00 rolled over", and a Coffee category is listed.

SourceKit often shows errors across files (for example "Cannot find 'BudgetStore' in scope"). Those are noise. Trust `xcodebuild`.

## Sharing

- AltStore (Rahul and his girlfriend): `build_ipa.sh`, then My Apps → + → pick the .ipa. With a free Apple ID, it expires after 7 days unless AltServer refreshes it.
- Rahul's phone: his Mac's `~/PhoneApps/phoneapps update budget` pulls this repo, re-signs the .ipa under the ID already on his phone (`com.rahuldas.weeklybudget.9CRNY4RH2T`), backs up `budget-v2.json`, installs and checks the data is still there. Don't install on his phone any other way.
- Anyone on AltStore: update through AltStore with the new .ipa, never a different tool.
- An App Store or TestFlight release would need the $99 a year Apple Developer Program. Rahul doesn't have it.
