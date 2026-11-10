#!/bin/bash
# Assemble an unsigned, ad-hoc-signed app bundle. No Developer ID required.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' "$ROOT/Sources/QForEmailCore/Version.swift")"
test -n "$VERSION"
BIN="$ROOT/.build/release/QForEmail"
test -x "$BIN"
APP="$ROOT/dist/Q for Email.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/QForEmail"
if [[ -x "$ROOT/scripts/make-icon.py" ]] || [[ -f "$ROOT/scripts/make-icon.py" ]]; then
  python3 "$ROOT/scripts/make-icon.py" "$APP/Contents/Resources/AppIcon.icns" || true
fi
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>QForEmail</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>xyz.cdr.q-for-email</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Q for Email</string>
  <key>CFBundleDisplayName</key>
  <string>Q for Email</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Q for Email reads Inbox subjects and short excerpts, creates Q mailboxes, and moves non-essential mail out of the Inbox. It never deletes or sends mail.</string>
</dict>
</plist>
EOF
codesign --force --sign - "$APP"
echo "Assembled $APP"
