#!/bin/zsh
# Build for the simulator, seed a scenario, launch, and screenshot.
# Usage: test_sim.sh <scenario> <screenshot.png>
#   fresh     no save file (first-run budgets sheet should appear)
#   thisweek  current week, Food over budget, a custom "Coffee" category, some rollover
#   lastweek  save file from last week (Food $30 of 100, Uber $60 of 50) → reopening must roll over Food +70, Uber +0
#   legacy    v1.0 save file (budget.json) from last week → must migrate to budget-v2.json and roll over
#   import    thisweek data plus sample-statement.png in Documents; opens the screenshot import sheet
#   keep      leave whatever data is there
# Extra launch arguments: LAUNCH_ARGS="-showHistory YES" test_sim.sh lastweek shot.png
set -e
SCEN=${1:-thisweek}; SHOT=${2:-$TMPDIR/budget.png}
ROOT="$(git -C "${0:A:h}" rev-parse --show-toplevel)"
PROJ=$ROOT; BID=com.rahuldas.weeklybudget
cd $PROJ
xcodegen generate -q
xcodebuild -project WeeklyBudget.xcodeproj -scheme WeeklyBudget -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build -quiet
DEV=$(xcrun simctl list devices available | grep -m1 -E 'iPhone 1[6-9]' | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot $DEV 2>/dev/null || true
xcrun simctl bootstatus $DEV -b >/dev/null
xcrun simctl terminate $DEV $BID 2>/dev/null || true
[[ $SCEN != keep ]] && xcrun simctl uninstall $DEV $BID 2>/dev/null || true
xcrun simctl install $DEV build/Build/Products/Debug-iphonesimulator/WeeklyBudget.app
DOCS="$(xcrun simctl get_app_container $DEV $BID data)/Documents"; mkdir -p "$DOCS"
python3 "${0:A:h}/seed.py" "$SCEN" "$DOCS"
[[ $SCEN == import ]] && LAUNCH_ARGS="-importFiles sample-statement.png $LAUNCH_ARGS"
xcrun simctl launch $DEV $BID ${=LAUNCH_ARGS} >/dev/null
sleep 9   # first launch after boot can show a blank frame for a few seconds
xcrun simctl io $DEV screenshot "$SHOT" >/dev/null 2>&1
echo "Screenshot: $SHOT"
[[ -f "$DOCS/budget-v2.json" ]] && python3 -c "
import json;s=json.load(open('$DOCS/budget-v2.json'))
print('Saved:', [(c['name'],c['budget'],c['rollover']) for c in s['categories']], '| expenses:', len(s['expenses']))"
rm -rf build
