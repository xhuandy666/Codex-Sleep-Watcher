#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
for ARCH in arm64 x86_64; do
    # Keep each architecture isolated: newer SwiftPM layouts share a bin directory.
    swift build --scratch-path "$ROOT/.build/package-$ARCH" -c release --arch "$ARCH" --product CodexSleepWatcherApp
    swift build --scratch-path "$ROOT/.build/package-$ARCH" -c release --arch "$ARCH" --product codex-sleep-hook
done
ARM_BIN_DIR="$(swift build --scratch-path "$ROOT/.build/package-arm64" -c release --arch arm64 --show-bin-path)"
INTEL_BIN_DIR="$(swift build --scratch-path "$ROOT/.build/package-x86_64" -c release --arch x86_64 --show-bin-path)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
DIST="$ROOT/dist"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/codex-sleep-watcher.XXXXXX")"
APP="$STAGE/Codex Sleep Watcher.app"
ZIP="$DIST/Codex-Sleep-Watcher-$VERSION.zip"
LEGACY_APP="$DIST/Codex Sleep Watcher.app"
trap '/bin/rm -rf "$STAGE"' EXIT

mkdir -p "$DIST"
/bin/rm -rf "$LEGACY_APP"
/bin/rm -f "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
/usr/bin/lipo -create \
    "$ARM_BIN_DIR/CodexSleepWatcherApp" \
    "$INTEL_BIN_DIR/CodexSleepWatcherApp" \
    -output "$APP/Contents/MacOS/CodexSleepWatcherApp"
/usr/bin/lipo -create \
    "$ARM_BIN_DIR/codex-sleep-hook" \
    "$INTEL_BIN_DIR/codex-sleep-hook" \
    -output "$APP/Contents/Helpers/codex-sleep-hook"
for ARCH in arm64 x86_64; do
    /usr/bin/lipo "$APP/Contents/MacOS/CodexSleepWatcherApp" -verify_arch "$ARCH"
    /usr/bin/lipo "$APP/Contents/Helpers/codex-sleep-hook" -verify_arch "$ARCH"
done
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
chmod 755 "$APP/Contents/MacOS/CodexSleepWatcherApp" "$APP/Contents/Helpers/codex-sleep-hook"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
xattr -cr "$APP"
codesign --verify --deep --strict "$APP"
/usr/bin/ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$APP" "$ZIP"
unzip -tq "$ZIP" >/dev/null
print -r -- "$ZIP"
