#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_app="$PWD/.build/DerivedData/Build/Products/Release/Codex Usage.app"
destination="$HOME/Applications/Codex Usage.app"
[[ -d "$source_app" ]] || { echo 'Run Scripts/build.sh first.' >&2; exit 1; }
if pgrep -x 'Codex Usage' >/dev/null; then
  echo 'Quit Codex Usage before installing an update.' >&2; exit 1
fi
mkdir -p "$HOME/Applications"
ditto "$source_app" "$destination"
codesign --verify --deep --strict "$destination"
open "$destination"
echo "Installed: $destination"
