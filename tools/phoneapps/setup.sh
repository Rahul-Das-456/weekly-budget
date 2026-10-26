#!/bin/zsh
# One-time setup of phoneapps on THIS Mac for THIS person's iPhone (plug it in, unlocked, trusted).
# Finds the iPhone, the Apple Development team signed in to Xcode, and the bundle ID Weekly Budget is
# already installed under, so updates land on the same app and its data stays.
# Writes ~/PhoneApps (phoneapps, apps.json, enable-auto-refresh.sh). Safe to run again.
set -e
HERE="${0:A:h}"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
mkdir -p ~/PhoneApps
cp "$HERE/phoneapps" "$HERE/enable-auto-refresh.sh" ~/PhoneApps/
chmod +x ~/PhoneApps/phoneapps ~/PhoneApps/enable-auto-refresh.sh
command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen"; exit 1; }

python3 - "$REPO" <<'PY'
import json, os, subprocess, sys, tempfile
repo = sys.argv[1]
def dj(args):
    t = tempfile.mktemp(suffix=".json")
    subprocess.run(["xcrun", "devicectl", *args, "--json-output", t, "-q"], check=True, capture_output=True)
    return json.load(open(t))["result"]

phones = [d for d in dj(["list", "devices"])["devices"]
          if d.get("hardwareProperties", {}).get("deviceType") == "iPhone"
          and d.get("connectionProperties", {}).get("pairingState") == "paired"]
if not phones:
    sys.exit("No paired iPhone found. Plug it in, unlock it, tap Trust, then run this again.")
if len(phones) > 1:
    print("More than one iPhone; using the first:", [p["deviceProperties"]["name"] for p in phones])
phone = phones[0]
device = phone["identifier"]

# The team of the Apple Development certificate Xcode signs with (OU field of the cert).
pem = subprocess.run(["security", "find-certificate", "-a", "-c", "Apple Development", "-p"], capture_output=True, text=True).stdout
if "BEGIN CERTIFICATE" not in pem:
    sys.exit("No Apple Development certificate. In Xcode: Settings > Accounts > add your Apple ID, then Manage Certificates > + Apple Development.")
first = pem.split("-----END CERTIFICATE-----")[0] + "-----END CERTIFICATE-----\n"
subj = subprocess.run(["openssl", "x509", "-noout", "-subject", "-nameopt", "multiline"], input=first, capture_output=True, text=True).stdout
team = next(l.split("=", 1)[1].strip() for l in subj.splitlines() if "organizationalUnitName" in l)

apps = dj(["device", "info", "apps", "--device", device])["apps"]
found = [a["bundleIdentifier"] for a in apps if a["bundleIdentifier"].startswith("com.rahuldas.weeklybudget")]
if found:
    bundle = found[0]
    print(f"Weekly Budget is already on the phone as {bundle}; updates will use that ID so its data stays.")
    if len(found) > 1:
        print("  Note: more than one copy is installed:", found, "- using the first. Delete the one you don't use.")
    if bundle.count(".") == 3 and not bundle.endswith(team):
        print(f"  Warning: that copy was signed by team {bundle.rsplit('.',1)[1]}, but Xcode here signs as {team}.")
        print("  Use the same Apple ID in Xcode as in AltStore, or updates can't replace it.")
else:
    bundle = f"com.rahuldas.weeklybudget.{team}"
    print(f"Weekly Budget isn't on the phone yet; it will install as {bundle}.")

cfg = {"device": device, "team": team, "refreshAfterDays": 4, "keepBackups": 10, "apps": [{
    "key": "budget", "name": "Weekly Budget", "project": repo, "xcodeproj": "WeeklyBudget.xcodeproj",
    "scheme": "WeeklyBudget", "bundleId": bundle, "repo": "https://github.com/Rahul-Das-456/weekly-budget",
    "ipa": "WeeklyBudget.ipa", "autoUpdate": True}]}
path = os.path.expanduser("~/PhoneApps/apps.json")
if os.path.exists(path):
    old = json.load(open(path))
    keep = [a for a in old.get("apps", []) if a["key"] != "budget"]   # don't drop other apps someone added
    cfg["apps"] = keep + cfg["apps"]
json.dump(cfg, open(path, "w"), indent=2)
print(f"Wrote {path}: phone {phone['deviceProperties']['name']}, team {team}.")
PY
echo
echo "Next:  ~/PhoneApps/phoneapps update budget        # install the repo's .ipa, data kept"
echo "Then:  ~/PhoneApps/enable-auto-refresh.sh         # re-sign every few days + pick up new versions"
