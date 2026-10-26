# Weekly Budget: notes for Claude

You're working on Weekly Budget, a small SwiftUI iPhone app shared by Rahul and his girlfriend. Both of them (and their Claude sessions) push to this repo: https://github.com/Rahul-Das-456/weekly-budget. This file is the handoff from Rahul's Claude Code session, so you start knowing what it knew.

For changes, tests, new .ipa builds and pushes, use the project skill **budget-tracker** in `.claude/skills/budget-tracker/` (Claude Code loads it from this repo). Its `references/app.md` has the full architecture.

## The three rules that protect people's data

People already have real budgets on their phones. Breaking any of these makes a phone show an empty app.

1. **Never change `PRODUCT_BUNDLE_IDENTIFIER` (`com.rahuldas.weeklybudget`) in `project.yml`.** iOS keeps an app's data only when an update has the same bundle ID. AltStore appends the installer's team ID (`com.rahuldas.weeklybudget.<TEAM>`), and that only stays stable if the ID in the .ipa stays the same. If Xcode says the ID is taken on someone's account, don't commit an ID change; sign locally with a different ID and leave the repo alone.
2. **Never stop reading an older save file.** Data is `Documents/budget-v2.json`. New fields must be optional (like `history: [WeekRecord]?` in 1.2) or come with a migration. Version 1.0's `Documents/budget.json` is still migrated by `LegacyState`. Test the `legacy` scenario after any change to saving or loading.
3. **Update phones with the same tool that installed the app.** The app's own alerts (1.3) tell each person which tool that is. Rahul's phone: his Mac's `~/PhoneApps/phoneapps update budget` (pulls this repo, re-signs the .ipa under the ID already on his phone, backs up, verifies). Anyone using AltStore: AltStore → My Apps → + → the new `WeeklyBudget.ipa`. Switching tools gives the app a new ID and leaves the data behind.

## Before you start

- `git pull --rebase origin main` first. The other person may have pushed. Never force-push. If a pull conflicts, stop and ask.
- Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` for any shipped change.
- Rebuild `WeeklyBudget.ipa` (`.claude/skills/budget-tracker/scripts/build_ipa.sh`) and commit it with the code, so the repo's .ipa always matches the source.
- Keep `README.md` accurate; it's what a person reads.
- The person you're helping likes short, plain answers. No em dashes.

## History (what's been done)

| Version | Who | What |
|---|---|---|
| 1.0 | Rahul's Claude | Four fixed categories, weekly budget per category, expenses, Monday reset. |
| 1.1 | Rahul's Claude | Custom categories (name, icon, budget, reorder, delete), rollover of unused money, new save file `budget-v2.json` with migration from 1.0. |
| 1.2 | Girlfriend's side (PRs #1, #2) | Edit expenses, Past weeks history (`WeekRecord`, optional `history` field), themes (`Theme.swift`: Match phone, Light, Dark, Pink, Hacker). |
| 1.3 | Rahul's Claude | `AppUpkeep.swift`: notifications 48 h, 24 h and 3 h before the signing profile expires, a banner in the last 2 days, and a new-version check against this repo's `project.yml` (every 6 h). Wording depends on how it was installed (AltStore adds `ALTDeviceID` to Info.plist). Debug args: `-signingExpiresInHours N`, `-upkeepFakeRemoteVersion X`. `tools/phoneapps` now refreshes at 4 days and opens the app after installing so it reschedules the alerts. |

Rollover rule: on a new week, each category's `rollover = max(0, budget + rollover - spent)`, plus a full budget for each extra week the app wasn't opened; then expenses clear. Overspending never reduces next week. In 1.2 the finished week is saved to history first (only if it had expenses).

## Tools you need on the Mac

Xcode 16+, and XcodeGen (`brew install xcodegen`); the Xcode project is generated from `project.yml`. Tests run in the iPhone simulator, no phone needed.
