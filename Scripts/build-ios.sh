#!/usr/bin/env bash
# Build an unsigned iOS device app and package it for LiveContainer/sideloading.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Prefer the xcode-select'ed toolchain (CI 的 setup-xcode 会切换), 
# 本地未配置时回退到默认 Xcode 路径。
if command -v xcodebuild >/dev/null 2>&1; then
  XCODEBUILD="$(command -v xcodebuild)"
else
  XCODEBUILD="/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"
fi
DERIVED="$ROOT/.build/xcode-ios"
APP="$DERIVED/Build/Products/Release-iphoneos/BMusic.app"
OUT="$ROOT/build"

cd "$ROOT"

if [[ ! -d BMusic.xcodeproj ]]; then
  echo "BMusic.xcodeproj is missing; run xcodegen generate first." >&2
  exit 1
fi

echo "▸ Building BMusic for iOS (arm64, Release)…"
"$XCODEBUILD" \
  -project BMusic.xcodeproj \
  -scheme BMusic-iOS \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

echo "▸ Packaging unsigned IPA…"
rm -rf "$OUT/ios/Payload"
mkdir -p "$OUT/ios/Payload"
cp -R "$APP" "$OUT/ios/Payload/BMusic.app"
rm -f "$OUT/BMusic-unsigned.ipa"
(cd "$OUT/ios" && /usr/bin/zip -qry ../BMusic-unsigned.ipa Payload)

echo "▸ Built $OUT/BMusic-unsigned.ipa"
