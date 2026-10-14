#!/usr/bin/env bash
# Builds the Release app with N classes and the patch on or off, then measures memory
# at the first screen over several cold launches. Appends one row per run to results/raw.csv.
# The app stays open after the last run so the screen can be checked.
#
# Usage: scripts/bench.sh <ios|android> <N> <on|off> [runs]
#   iOS:     IOS_UDID=<booted simulator udid>  -> phys_footprint (footprint(1))
#   Android: ANDROID_SERIAL=<emulator serial>  -> TOTAL PSS and Native Heap PSS (dumpsys meminfo)
#   SETTLE_SECONDS (default 15) is the wait between launch and sample.
set -euo pipefail
cd "$(dirname "$0")/.."

platform=${1:?platform}
n=${2:?N}
patch=${3:?on|off}
runs=${4:-5}
settle=${SETTLE_SECONDS:-15}
app_id=com.example.createclassrepro
csv=results/raw.csv

[[ "$runs" =~ ^[1-9][0-9]*$ ]] || { echo "runs must be a positive integer" >&2; exit 1; }
node scripts/gen-classes.mjs "$n"
scripts/set-patch.sh "$patch"
expected="classbench: classes=$n/$n factory=$([ "$patch" = on ] && echo yes || echo no)"
mkdir -p results
[ -f "$csv" ] || echo "platform,classes,patch,run,metric,kb,native_heap_kb,time" > "$csv"

# The app reports its first screen through ClassBench.report(); fail if it is not the expected one.
check_screen() { # log
  grep -qF "$expected" <<<"$1" || { printf 'expected "%s" in the app log, got:\n%s\n' "$expected" "$1" >&2; exit 1; }
}
require_number() { # name value
  [[ "$2" =~ ^[0-9]+$ ]] || { echo "could not read $1 (got '$2')" >&2; exit 1; }
}
record() { # run metric kb native_heap_kb
  echo "$platform,$n,$patch,$1,$2,$3,$4,$(date -u +%FT%TZ)" | tee -a "$csv"
}

case "$platform" in
  ios)
    udid=${IOS_UDID:?set IOS_UDID}
    [ -d ios ] || npx expo prebuild --platform ios --no-install
    [ -d ios/Pods ] || (cd ios && pod install)
    xcodebuild -workspace ios/createclassrepro.xcworkspace -scheme createclassrepro \
      -configuration Release -sdk iphonesimulator -destination "id=$udid" \
      -derivedDataPath build/ios -quiet build
    xcrun simctl install "$udid" build/ios/Build/Products/Release-iphonesimulator/createclassrepro.app
    for ((run = 1; run <= runs; run++)); do
      xcrun simctl terminate "$udid" "$app_id" 2>/dev/null || true
      sleep 2
      pid=$(xcrun simctl launch "$udid" "$app_id" | awk '{print $NF}')
      sleep "$settle"
      kill -0 "$pid" || { echo "app exited before sampling" >&2; exit 1; }
      check_screen "$(xcrun simctl spawn "$udid" log show --last 2m --style compact \
        --predicate "processIdentifier == $pid AND eventMessage BEGINSWITH 'classbench:'")"
      bytes=$(footprint -f bytes --pid "$pid" | sed -n 's/.*Footprint: \([0-9]*\) B.*/\1/p' | head -1)
      require_number phys_footprint "$bytes"
      record "$run" phys_footprint $((bytes / 1024)) ""
    done
    ;;
  android)
    adb=(adb -s "${ANDROID_SERIAL:?set ANDROID_SERIAL}")
    [ -d android ] || npx expo prebuild --platform android --no-install
    (cd android && ./gradlew -q assembleRelease -PreactNativeArchitectures=arm64-v8a)
    "${adb[@]}" install -r android/app/build/outputs/apk/release/app-release.apk >/dev/null
    for ((run = 1; run <= runs; run++)); do
      "${adb[@]}" shell am force-stop "$app_id"
      sleep 2
      "${adb[@]}" shell am start -W -n "$app_id/.MainActivity" >/dev/null
      sleep "$settle"
      pid=$("${adb[@]}" shell pidof "$app_id" || true)
      require_number pid "$pid"
      check_screen "$("${adb[@]}" logcat -d --pid="$pid" -s ClassBench:I)"
      meminfo=$("${adb[@]}" shell dumpsys meminfo "$pid")
      total=$(awk '/TOTAL PSS:/ {print $3}' <<<"$meminfo")
      native=$(awk '$1 == "Native" && $2 == "Heap" {print $3; exit}' <<<"$meminfo")
      require_number "TOTAL PSS" "$total"
      require_number "Native Heap PSS" "$native"
      record "$run" total_pss "$total" "$native"
    done
    ;;
  *) echo "platform must be ios or android" >&2; exit 1 ;;
esac
