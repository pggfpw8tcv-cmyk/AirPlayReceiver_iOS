#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
bash scripts/build_dependencies.sh iphonesimulator
python3 scripts/collect_licenses.py
xcodegen generate --spec project.yml
SIMULATOR_ID="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(v["udid"] for k,items in d["devices"].items() if "iOS-18-5" in k for v in items if "iPhone" in v["name"]))')"
xcodebuild -project AirPlayReceiver.xcodeproj -scheme Receiver -configuration Debug \
  -sdk iphonesimulator -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath build/Simulator -resultBundlePath build/SimulatorTests.xcresult \
  CODE_SIGNING_ALLOWED=NO test
