#!/usr/bin/env bash
# check-infoplist.sh — assert the shipped Info.plist stays complete & truthful
# after `xcodegen generate`.
#
# WHY: project.yml once carried an `info:` block whose `properties:` WROTE
# Resources/iOS/Info.plist at generate-time, clobbering the hand-maintained plist.
# That silently DROPPED NSLocationWhenInUseUsageDescription (→ App Store rejection
# ITMS-90683 + killed "Place in session name") and shipped a FALSE
# NSHealthUpdateUsageDescription ("it does not write any data to Apple Health")
# while HealthKitWriter DOES write HR + respiratory rate. The `info:` block is gone;
# this guard fails the build if it (or the regression it caused) ever comes back.
#
# Run AFTER `xcodegen generate` so it validates the plist the build actually uses.
set -euo pipefail

PLIST="Resources/iOS/Info.plist"
fail=0

echo "== Info.plist hygiene guard =="

if [ ! -f "$PLIST" ]; then
  echo "FAIL: $PLIST is missing"
  exit 1
fi

# 1) Required privacy usage strings must be present (missing = App Store rejection).
#
# ⛔ #1013 — THIS LIST GUARDED SIX OF THE NINE STRINGS THE PLIST ACTUALLY SHIPS, so three
# could be deleted or renamed and nothing here would notice. Measured with
# `grep -o 'NS[A-Za-z]*UsageDescription' Resources/iOS/Info.plist | sort -u` → nine; the
# list held six. The three that were unguarded are exactly the ones whose feature was added
# AFTER this guard was written, which is how a required-keys list rots: it is complete on
# the day it is typed and never re-derived.
#
# ⭐ THE AUDIT NAMED ONE OF THE THREE; MEASURING FOUND THREE. That is the #766/#768 law in
# a new place — "all of them" only ever means "all of them I enumerated". The cheap check is
# the grep above, not a re-read of the list.
#
# Why each of the three is genuinely required, i.e. why this is not just tidying:
#   · NSPhotoLibraryAdd — the still shutter and the finished visual take both write to
#     Photos. Missing string = the write throws and the take vanishes with no message.
#   · NSBluetoothAlways / NSBluetoothPeripheral — the universal BLE heart-rate belt (0x180D)
#     is built AND wired; its door is the pulse pill's source dropdown. Missing string = iOS
#     kills the app on the first scan.
required_keys=(
  NSLocationWhenInUseUsageDescription
  NSCameraUsageDescription
  NSMicrophoneUsageDescription
  NSHealthShareUsageDescription
  NSHealthUpdateUsageDescription
  NSLocalNetworkUsageDescription
  NSPhotoLibraryAddUsageDescription
  NSBluetoothAlwaysUsageDescription
  NSBluetoothPeripheralUsageDescription
)
for key in "${required_keys[@]}"; do
  if grep -q "$key" "$PLIST"; then
    echo "  ok: $key present"
  else
    echo "  FAIL: $key MISSING from $PLIST"
    fail=1
  fi
done

# 1b) The PAIRED check, and it goes the OTHER way (#1013). The loop above catches a key being
#      DELETED from the plist; it cannot catch one being ADDED without being guarded — which is
#      exactly how the list came to hold six of nine. So: every usage string the plist ships must
#      also appear in required_keys.
#
#      ⚠️ THE LIST STAYS HAND-WRITTEN ON PURPOSE. Deriving required_keys FROM the plist would
#      make this file agree with itself and never fail: deleting a key would delete it from the
#      derived list too. The literal IS the second opinion; this check only makes the second
#      opinion notice when the first one grows.
plist_keys=$(grep -o 'NS[A-Za-z]*UsageDescription' "$PLIST" | sort -u)
for key in $plist_keys; do
  case " ${required_keys[*]} " in
    *" $key "*) ;;
    *)
      echo "  FAIL: $PLIST ships $key but check-infoplist.sh does not guard it."
      echo "        Add it to required_keys — an unguarded string can be dropped silently,"
      echo "        and a dropped string is a launch crash or a silently-failing feature."
      fail=1
      ;;
  esac
done

# 2) The FALSE health-write claim must never reappear (HealthKitWriter DOES write).
if grep -qi "does not write any data to Apple Health" "$PLIST"; then
  echo "  FAIL: false NSHealthUpdate claim present — HealthKitWriter writes HR+respiratory"
  fail=1
else
  echo "  ok: no false 'does not write to Apple Health' claim"
fi

# 2b) bluetooth-peripheral background mode must stay OUT — no CBPeripheralManager
#     exists in the app, so declaring it is an unbacked capability (Guideline 2.5.4).
if grep -q '<string>bluetooth-peripheral</string>' "$PLIST"; then
  echo "  FAIL: bluetooth-peripheral background mode present — no CBPeripheralManager backs it (2.5.4 risk)"
  fail=1
else
  echo "  ok: no unbacked bluetooth-peripheral background mode"
fi

# 3) project.yml must NOT re-introduce an `info:` block that WRITES the main app
#    plist ($PLIST) — that clobbers the committed file at generate-time. (The
#    AUv3/Widgets/Watch extension `info:` blocks write their OWN plists and are fine.)
if grep -qE "path:[[:space:]]*${PLIST}" project.yml \
   && grep -A2 -E "path:[[:space:]]*${PLIST}" project.yml | grep -q 'properties:'; then
  echo "  FAIL: project.yml has an 'info:' block writing $PLIST — it overwrites the committed plist at generate time"
  fail=1
else
  echo "  ok: no project.yml 'info:' block writes $PLIST (committed plist is single source of truth)"
fi

if [ "$fail" -ne 0 ]; then
  echo "== Info.plist hygiene guard FAILED =="
  exit 1
fi
echo "== Info.plist hygiene guard PASSED =="
