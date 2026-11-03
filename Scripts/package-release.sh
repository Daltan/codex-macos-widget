#!/bin/bash
# Package the Release app produced by build.sh. No credentials or user data are copied.
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/.build/DerivedData/Build/Products/Release/Codex Usage.app"
[[ -d "$app" ]] || { echo 'Run Scripts/build.sh first.' >&2; exit 1; }
codesign --verify --deep --strict "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
[[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ && "$build" =~ ^[0-9]+$ ]] || {
    echo 'Invalid bundle version.' >&2; exit 1;
}
for binary in "$app/Contents/MacOS/Codex Usage" \
    "$app/Contents/PlugIns/CodexUsageWidget.appex/Contents/MacOS/CodexUsageWidget"; do
    architectures=" $(lipo -archs "$binary") "
    [[ "$architectures" == *' arm64 '* && "$architectures" == *' x86_64 '* ]] || {
        echo "Missing universal architectures: $binary ($architectures)" >&2; exit 1;
    }
done
name="Codex-Usage-${version}-${build}-universal"
output="$PWD/.build/releases/$name"
mkdir -p "$output"
staging=$(mktemp -d "$PWD/.build/package.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/Codex Usage.app"
ln -s /Applications "$staging/Applications"
cp Docs/INSTALL.txt "$staging/INSTALL.txt"
# Replacing a local package is safe; uploading never overwrites a published asset.
rm -f "$output/$name.dmg" "$output/$name.zip"
hdiutil create -volname 'Codex Usage' -srcfolder "$staging" \
    -format UDZO -ov "$output/$name.dmg"
hdiutil verify "$output/$name.dmg"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/$name.zip"
cp Docs/INSTALL.txt "$output/INSTALL.txt"
(
    cd "$output"
    shasum -a 256 "$name.dmg" "$name.zip" INSTALL.txt > SHA256SUMS.txt
)
echo "Release files: $output"
