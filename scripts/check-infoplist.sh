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
required_keys=(
  NSLocationWhenInUseUsageDescription
  NSCameraUsageDescription
  NSMicrophoneUsageDescription
  NSHealthShareUsageDescription
  NSHealthUpdateUsageDescription
  NSLocalNetworkUsageDescription
)
for key in "${required_keys[@]}"; do
  if grep -q "$key" "$PLIST"; then
    echo "  ok: $key present"
  else
    echo "  FAIL: $key MISSING from $PLIST"
    fail=1
  fi
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
