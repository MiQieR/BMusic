#!/usr/bin/env bash
# Build BMusic and wrap the SwiftPM executable in a proper .app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Prefer the Xcode toolchain over any swiftly shim on PATH. The current SDK
# swiftinterfaces use compiler flags that older toolchains do not understand.
TOOLCHAIN="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/bin"
if [[ -x "$TOOLCHAIN/swift" ]]; then
  export PATH="$TOOLCHAIN:$PATH"
fi
CONFIG="${1:-debug}"

export CLANG_MODULE_CACHE_PATH="$ROOT/.build/clang-module-cache"
export SWIFT_MODULE_CACHE_PATH="$ROOT/.build/swift-module-cache"
# Keep package resolution non-interactive: no credential prompts and no
# terminal password questions while building an open-source dependency.
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/usr/bin/false

SPM_FLAGS=(
  --package-path "$ROOT"
  -c "$CONFIG"
  --disable-sandbox
  --cache-path "$ROOT/.build/spm-cache"
  --config-path "$ROOT/.build/spm-config"
)

echo "▸ Building BMusic ($CONFIG)…"
swift build "${SPM_FLAGS[@]}"

BIN_DIR="$(swift build "${SPM_FLAGS[@]}" --show-bin-path)"
APP="$ROOT/build/BMusic.app"
CONTENTS="$APP/Contents"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/BMusic" "$CONTENTS/MacOS/BMusic"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

if [[ -f "$ROOT/Resources/BMusic.icns" ]]; then
  cp "$ROOT/Resources/BMusic.icns" "$CONTENTS/Resources/BMusic.icns"
fi

printf 'APPL????' > "$CONTENTS/PkgInfo"

# Ad-hoc signing only. No developer identity, no keychain lookup.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || {
  echo "warning: ad-hoc codesign failed; the app can still be launched locally" >&2
}

echo "▸ Built $APP"
