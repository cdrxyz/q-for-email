#!/bin/bash
# Unsigned disk image. hdiutil does not need a Developer ID.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' "$ROOT/Sources/QForEmailCore/Version.swift")"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$ROOT/dist/Q for Email.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Q for Email" -srcfolder "$STAGE" -ov -format UDZO \
  "$ROOT/dist/Q-for-Email-${VERSION}-arm64.dmg"
echo "Wrote dist/Q-for-Email-${VERSION}-arm64.dmg"
(cd "$ROOT/dist" && shasum -a 256 Q-for-Email-*-arm64.zip Q-for-Email-*-arm64.dmg > SHA256SUMS.txt)
