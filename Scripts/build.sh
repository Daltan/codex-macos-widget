#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcodebuild -project CodexUsage.xcodeproj -scheme CodexUsage -configuration Release \
  -derivedDataPath .build/DerivedData build
codesign --verify --deep --strict '.build/DerivedData/Build/Products/Release/Codex Usage.app'
echo "Built: $PWD/.build/DerivedData/Build/Products/Release/Codex Usage.app"
