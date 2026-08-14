#!/bin/bash
# Builds Lucky Dangle into a local .app bundle. No network, no dependencies.
set -e

APP="LuckyDangle"
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/build/$APP.app"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Swift compiler not found. Install the Xcode command line tools first:"
  echo "  xcode-select --install"
  exit 1
fi

echo "→ Cleaning"
rm -rf "$DIR/build"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"

echo "→ Compiling"
xcrun swiftc -O "$DIR/main.swift" -o "$OUT/Contents/MacOS/$APP"

echo "→ Writing Info.plist"
cat > "$OUT/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>Lucky Dangle</string>
  <key>CFBundleDisplayName</key>       <string>Lucky Dangle</string>
  <key>CFBundleExecutable</key>        <string>LuckyDangle</string>
  <key>CFBundleIdentifier</key>        <string>local.luckydangle</string>
  <key>CFBundleVersion</key>           <string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>LSMinimumSystemVersion</key>    <string>12.0</string>
  <key>LSUIElement</key>               <true/>
  <key>NSHighResolutionCapable</key>   <true/>
</dict>
</plist>
PLIST

echo "→ Ad-hoc signing"
codesign --force --sign - "$OUT" >/dev/null 2>&1 || echo "  (skipped — not required)"

echo
echo "Built: $OUT"
echo "Run it:            open \"$OUT\""
echo "Install it:        cp -R \"$OUT\" /Applications/"
