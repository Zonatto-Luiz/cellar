#!/bin/bash
# Build Cellar.app (SwiftUI) with the cellar CLI bundled inside, and install it to /Applications.
# Usage: build-app.sh [install-dir]   (default: /Applications, or ~/Applications if not writable)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/build"
APP="$OUT/Cellar.app"
DEST="${1:-}"
if [ -z "$DEST" ]; then
  if [ -w /Applications ]; then DEST=/Applications; else DEST="$HOME/Applications"; fi
fi

log() { echo "==> $*"; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

log "Compiling"
swiftc -O -parse-as-library -target arm64-apple-macos14 \
  -o "$APP/Contents/MacOS/Cellar" "$ROOT/app/CellarApp.swift"

log "Bundling the cellar CLI"
cp "$ROOT/cellar" "$APP/Contents/Resources/cellar"
chmod +x "$APP/Contents/Resources/cellar"

log "Drawing the icon"
ICONSET="$OUT/Cellar.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
swiftc -O -o "$OUT/make-icon" "$ROOT/app/MakeIcon.swift"
"$OUT/make-icon" "$OUT/icon-1024.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$OUT/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$OUT/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Cellar.icns"

cat >"$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Cellar</string>
  <key>CFBundleIdentifier</key><string>local.cellar.app</string>
  <key>CFBundleName</key><string>Cellar</string>
  <key>CFBundleDisplayName</key><string>Cellar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>Cellar</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign -f -s - "$APP" >/dev/null

log "Installing to $DEST"
mkdir -p "$DEST"
rm -rf "$DEST/Cellar.app"
cp -R "$APP" "$DEST/"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/Cellar.app" 2>/dev/null || true
log "Done: $DEST/Cellar.app"
