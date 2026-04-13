#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
STOP_SCRIPT="$ROOT_DIR/scripts/stop_running_macsimize.sh"

BUILD_SETTINGS=$(cd "$ROOT_DIR" && xcodebuild -showBuildSettings -scheme Macsimize 2>/dev/null)
TARGET_BUILD_DIR=$(printf '%s
' "$BUILD_SETTINGS" | awk -F' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / { print $2; exit }')
FULL_PRODUCT_NAME=$(printf '%s
' "$BUILD_SETTINGS" | awk -F' = ' '/^[[:space:]]*FULL_PRODUCT_NAME = / { print $2; exit }')
PRODUCT_BUNDLE_IDENTIFIER=$(printf '%s
' "$BUILD_SETTINGS" | awk -F' = ' '/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = / { print $2; exit }')

if [ -z "$TARGET_BUILD_DIR" ] || [ -z "$FULL_PRODUCT_NAME" ] || [ -z "$PRODUCT_BUNDLE_IDENTIFIER" ]; then
  echo "Unable to resolve Macsimize build settings" >&2
  exit 1
fi

SOURCE_APP="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
DEST_DIR="$HOME/Applications"
DEST_APP="$DEST_DIR/$FULL_PRODUCT_NAME"
LOG_FILE="${MACSIMIZE_LOG_FILE:-/tmp/macsimize-live.log}"
ERR_FILE="${MACSIMIZE_ERR_FILE:-/tmp/macsimize-live.stderr}"

if [ ! -d "$SOURCE_APP" ]; then
  echo "Built app not found at: $SOURCE_APP" >&2
  echo "Build the Macsimize scheme in Debug first, then rerun this script." >&2
  exit 1
fi

mkdir -p "$DEST_DIR"

if [ -x "$STOP_SCRIPT" ]; then
  "$STOP_SCRIPT"
fi

rm -rf "$DEST_APP"
ditto "$SOURCE_APP" "$DEST_APP"

defaults write "$PRODUCT_BUNDLE_IDENTIFIER" diagnosticsEnabled -bool true
defaults write "$PRODUCT_BUNDLE_IDENTIFIER" showMenuBarIcon -bool true

: > "$LOG_FILE"
: > "$ERR_FILE"

launchctl setenv MACSIMIZE_DEBUG_LOG 1
launchctl setenv MACSIMIZE_LOG_FILE "$LOG_FILE"

open -na "$DEST_APP"

sleep 2

PID=$(/usr/bin/pgrep -f "$DEST_APP/Contents/MacOS/" | tail -n 1 || true)

echo "Launched stable dev app"
echo "  app: $DEST_APP"
echo "  bundle id: $PRODUCT_BUNDLE_IDENTIFIER"
echo "  pid: ${PID:-unknown}"
echo "  log: $LOG_FILE"
echo "  stderr: $ERR_FILE"
echo
echo "Recent log output:"
tail -n 20 "$LOG_FILE" 2>/dev/null || true
