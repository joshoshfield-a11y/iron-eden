#!/usr/bin/env bash
# IRON EDEN build-loop gate: automated test -> Android debug export -> verify -> zip.
# Usage: tools/run-loop-gate.sh <version-label>   e.g. tools/run-loop-gate.sh v1.1-wave1
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=~/tools/godot/godot
LABEL="${1:?usage: run-loop-gate.sh <version-label>}"

echo "== GATE 1/4: automated playtest =="
"$GODOT" --headless --path . -- --iron-eden-test 2>&1 | tee /tmp/iron-eden-test.log
grep -q "IRON EDEN AUTO TEST: PASS" /tmp/iron-eden-test.log

echo "== GATE 2/4: Android debug export =="
"$GODOT" --headless --path . --export-debug Android build/iron-eden-slice.apk

echo "== GATE 3/4: signature + badging =="
export JAVA_HOME=~/jdk17
export PATH=~/jdk17/bin:$PATH
~/android-sdk/build-tools/36.1.0/apksigner verify build/iron-eden-slice.apk
~/android-sdk/build-tools/36.1.0/aapt2 dump badging build/iron-eden-slice.apk > /tmp/iron-eden-badging.txt || true
grep -m1 "^package:" /tmp/iron-eden-badging.txt || true
grep -m1 "minSdkVersion" /tmp/iron-eden-badging.txt || true

echo "== GATE 4/4: zip deliverable =="
mkdir -p ~/workspace/your_files
rm -f ~/workspace/your_files/iron-eden-"$LABEL".zip
cd build && zip -q ~/workspace/your_files/iron-eden-"$LABEL".zip iron-eden-slice.apk && cd ..
ls -l build/iron-eden-slice.apk ~/workspace/your_files/iron-eden-"$LABEL".zip
md5sum build/iron-eden-slice.apk
echo "LOOP GATE: PASS ($LABEL)"
