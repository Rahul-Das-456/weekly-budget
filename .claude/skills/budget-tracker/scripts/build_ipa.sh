#!/bin/zsh
# Build an unsigned Release .ipa for AltStore. Writes <repo>/WeeklyBudget.ipa (tracked in the repo) and copies it to ~/Desktop.
set -e
ROOT="$(git -C "${0:A:h}" rev-parse --show-toplevel)"
PROJ=$ROOT
cd $PROJ
xcodegen generate -q
xcodebuild -project WeeklyBudget.xcodeproj -scheme WeeklyBudget -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build -quiet
rm -rf build/ipa WeeklyBudget.ipa && mkdir -p build/ipa/Payload
cp -R build/Build/Products/Release-iphoneos/WeeklyBudget.app build/ipa/Payload/
(cd build/ipa && zip -qry ../../WeeklyBudget.ipa Payload)
rm -rf build
cp WeeklyBudget.ipa ~/Desktop/WeeklyBudget.ipa
[[ -d ~/Library/Mobile\ Documents/com~apple~CloudDocs/Sideload ]] && cp WeeklyBudget.ipa ~/Library/Mobile\ Documents/com~apple~CloudDocs/Sideload/ || true
VER=$(unzip -p WeeklyBudget.ipa Payload/WeeklyBudget.app/Info.plist | plutil -extract CFBundleShortVersionString raw -)
echo "Wrote WeeklyBudget.ipa v$VER to the repo and ~/Desktop. Install it with AltStore: My Apps → + → the file."
