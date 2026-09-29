#!/usr/bin/env bash
# Boots an iPhone simulator, installs a Debug build of the app, opens each main
# screen via the DEBUG-only -FRCScreenshotScene launch argument, and saves a
# screenshot of each. Fails if the app crashes. Runs in CI; works on any Mac:
#
#   scripts/capture-screenshots.sh path/to/FindRunClub.app screenshots/
set -euo pipefail

APP_PATH="$1"
OUT_DIR="$2"
BUNDLE_ID="com.findrunclub.app"
SETTLE_SECONDS="${SETTLE_SECONDS:-12}"
mkdir -p "$OUT_DIR"

DEVICE=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
runtimes = json.load(sys.stdin)["devices"]
iphones = [d for runtime, devices in sorted(runtimes.items(), reverse=True) if "iOS" in runtime
           for d in devices if d["name"].startswith("iPhone")]
preferred = [d for d in iphones if d["name"] in ("iPhone 16", "iPhone 16 Pro", "iPhone 15", "iPhone 15 Pro")]
print((preferred or iphones)[0]["udid"])
')
echo "Using simulator $DEVICE"

xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl install "$DEVICE" "$APP_PATH"
xcrun simctl privacy "$DEVICE" grant location "$BUNDLE_ID" || true
xcrun simctl location "$DEVICE" set 36.1580,-86.7760 || true
xcrun simctl status_bar "$DEVICE" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true

# shoot <file name> <scene> [weekday 1-7, 0 = today] [show everything YES/NO]
shoot() {
  local name="$1" scene="$2" weekday="${3:-0}" everything="${4:-NO}"
  local output pid
  output=$(SIMCTL_CHILD_TZ=America/Chicago xcrun simctl launch --terminate-running-process "$DEVICE" "$BUNDLE_ID" \
    -FRCScreenshotScene "$scene" -FRCScreenshotWeekday "$weekday" -FRCScreenshotShowEverything "$everything")
  pid="${output##* }"
  sleep "$SETTLE_SECONDS"
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "::error::The app is no longer running after launching scene '$scene' (pid $pid). It probably crashed."
    ls -t ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -i FindRunClub | head -1 | while read -r report; do
      head -80 ~/Library/Logs/DiagnosticReports/"$report"
    done
    exit 1
  fi
  xcrun simctl io "$DEVICE" screenshot "$OUT_DIR/$name.png" >/dev/null
  echo "Captured $name"
}

# Weekdays: 1 = Sunday ... 7 = Saturday. Tuesday matches the wireframes.
shoot 01-map-tuesday map 3
shoot 02-map-saturday map 7
shoot 03-list-expanded-tuesday expanded 3
shoot 04-filters filters 3
shoot 05-club-five-points detail 3
shoot 06-club-five-points-bottom detail-bottom 3
shoot 07-account account 3
# Last, because "show everything" is saved as the filter for later launches.
shoot 08-map-saturday-all-activities map 7 YES

xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" || true
