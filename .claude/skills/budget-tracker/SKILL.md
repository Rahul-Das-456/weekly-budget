---
name: budget-tracker
description: Changes, tests, builds and publishes the Weekly Budget iPhone app in this repo (SwiftUI, github.com/Rahul-Das-456/weekly-budget). The app sets a weekly budget per category, logs and edits expenses, resets every Monday and rolls unused money over, keeps past weeks, and has themes. Use when asked to add a feature to, fix, test, rebuild, make a new .ipa of, or push the budget app.
---

# Budget Tracker

You maintain the Weekly Budget app in this repo. Two people work on it and push to the same GitHub repo. Keep replies short and plain, with no em dashes. Read `CLAUDE.md` (repo root) and `references/app.md` before changing code.

## Before anything else

`git pull --rebase origin main`, so you build on the other person's latest work. If it conflicts, stop and ask. Never force-push.

Data safety, every time:
- Never change the bundle ID in `project.yml`. A new ID is a new, empty app on everyone's phone.
- Never stop reading older save files. New saved fields must be optional or migrated.
- Don't install on phones yourself unless asked. People update through the tool that installed their copy (AltStore, or Rahul's `phoneapps`).

## What to do, by request

| Asked | Do this |
|---|---|
| Add a feature / fix something | Edit `WeeklyBudget/*.swift`. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`. Test with `scripts/test_sim.sh` and look at the screenshot. Rebuild the .ipa, update `README.md` and `CLAUDE.md`'s history table, push. |
| "New .ipa" | `scripts/build_ipa.sh`. Writes `WeeklyBudget.ipa` at the repo root and a copy on the Desktop. |
| "Push" / "update GitHub" | `scripts/push_github.sh "message"`: commits, pulls with rebase, pushes. Uses your normal git login. |
| "Does it work?" | `scripts/test_sim.sh thisweek <tmp>/shot.png`, then look at the PNG. |

## Test before you report

```
.claude/skills/budget-tracker/scripts/test_sim.sh fresh    /tmp/shot.png   # first-run sheet
.claude/skills/budget-tracker/scripts/test_sim.sh thisweek /tmp/shot.png   # normal week, over budget, custom category
.claude/skills/budget-tracker/scripts/test_sim.sh lastweek /tmp/shot.png   # rollover after a week passes
.claude/skills/budget-tracker/scripts/test_sim.sh legacy   /tmp/shot.png   # a 1.0 save upgrades with nothing lost
```

Expected results are in `references/app.md`. The script can't tap through screens, so add a seed scenario or a launch argument for anything only reachable by tapping, or say you didn't click through it. Don't claim it works from the build alone.

## Shipping checklist

1. Pulled first; version bumped.
2. Matching `test_sim.sh` scenarios pass (and `legacy` if saving or loading changed).
3. `build_ipa.sh` succeeded; the new .ipa is committed with the code.
4. README and the CLAUDE.md history table updated.
5. `push_github.sh` succeeded.

## Files

- `references/app.md`: architecture, rules, save format, testing, sharing.
- `scripts/test_sim.sh` + `scripts/seed.py`: simulator build, seed data, screenshot, saved-state printout.
- `scripts/build_ipa.sh`: unsigned .ipa for AltStore.
- `scripts/push_github.sh`: commit, pull with rebase, push.
