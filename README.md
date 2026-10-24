# Weekly Budget

A simple iPhone app for a weekly budget.

- Set a weekly budget for each category. It starts with Food, Groceries, Entertainment and Uber / Lyft.
- Add your own categories, each with a name, a budget and an icon. You can also rename, reorder or delete them.
- Log an expense with an amount and an optional note.
- Every Monday, spending resets to $0. Unused money in each category rolls over to the next week. Going over doesn't reduce next week's budget.
- Everything is saved on the phone. There's no account and no server.

## Install with AltStore

Download `WeeklyBudget.ipa` from this repo. In AltStore, go to My Apps, tap **+**, and pick the file.

## Build from source

You need a Mac with Xcode 16 or newer. The app runs on iOS 17+.

1. Open `WeeklyBudget.xcodeproj` in Xcode.
2. Under **Signing & Capabilities**, pick your Apple ID as the Team. If the bundle ID is already taken, change it.
3. Plug in your iPhone, select it, and press Run.

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). If you change `project.yml`, run `xcodegen generate`.

## Files

- `WeeklyBudget/WeeklyBudgetApp.swift`: app entry point. It checks for a new week whenever the app opens.
- `WeeklyBudget/BudgetStore.swift`: data model, saving, the weekly reset and rollover, and migration from the 1.0 save format.
- `WeeklyBudget/ContentView.swift`: all the screens.
- `WeeklyBudget/Assets.xcassets`: app icon and accent color.
