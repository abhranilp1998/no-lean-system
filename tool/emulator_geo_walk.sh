#!/usr/bin/env bash
# Feeds an Android emulator mock fixes that walk in and out of a 200 m zone
# at Park Street, Kolkata (22.5726, 88.3639). Used by the REAL_LOCATION
# integration test and for manual zone-alert checks.
#   tool/emulator_geo_walk.sh [serial] [seconds-per-step]
set -euo pipefail
serial="${1:-emulator-5554}"
step="${2:-4}"
while true; do
  adb -s "$serial" emu geo fix 88.3639 22.5826 >/dev/null # ~1.1 km north
  sleep "$step"
  adb -s "$serial" emu geo fix 88.3639 22.5726 >/dev/null # zone centre
  sleep "$step"
done
