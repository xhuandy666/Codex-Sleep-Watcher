#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
swift build -c release --product CodexSleepWatcherApp
swift build -c release --product codex-sleep-hook
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$ROOT/dist/Codex Sleep Watcher.app"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers"
cp "$BIN_DIR/CodexSleepWatcherApp" "$APP/Contents/MacOS/CodexSleepWatcherApp"
cp "$BIN_DIR/codex-sleep-hook" "$APP/Contents/Helpers/codex-sleep-hook"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
chmod 755 "$APP/Contents/MacOS/CodexSleepWatcherApp" "$APP/Contents/Helpers/codex-sleep-hook"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
print -r -- "$APP"
