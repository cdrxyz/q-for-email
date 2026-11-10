#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' "$ROOT/Sources/QForEmailCore/Version.swift")"
cd "$ROOT/dist"
zip -r -y "Q-for-Email-${VERSION}-arm64.zip" "Q for Email.app"
shasum -a 256 "Q-for-Email-${VERSION}-arm64.zip"
echo "Wrote dist/Q-for-Email-${VERSION}-arm64.zip"
