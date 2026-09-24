#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
bash scripts/build_dependencies.sh iphoneos
python3 scripts/collect_licenses.py
xcodegen generate --spec project.yml
mkdir -p build/artifacts
xcodebuild -project AirPlayReceiver.xcodeproj -scheme Receiver -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  ARCHS=arm64 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  build | tee build/artifacts/xcodebuild.log
python3 scripts/package_ipa.py build/DerivedData/Build/Products/Release-iphoneos/Receiver.app \
  build/artifacts/AirPlayReceiver-unsigned.ipa
cp dependencies.lock.json build/artifacts/dependencies.lock.json
cp THIRD_PARTY_NOTICES.md build/artifacts/THIRD_PARTY_NOTICES.md
cp -R Resources/Licenses build/artifacts/Licenses
