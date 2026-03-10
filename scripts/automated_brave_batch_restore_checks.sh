#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_common.sh"

: "${BRAVE_APP_NAME:=Brave Browser}"
: "${BRAVE_BUNDLE_ID:=com.brave.Browser}"
: "${BRAVE_MIN_WINDOWS:=2}"

LOG_FILE=""

ensure_no_other_macsimize_instances() {
  pkill -x 'Macsimize Beta' >/dev/null 2>&1 || true
  pkill -f 'Macsimize Beta.app/Contents/MacOS/Macsimize Beta' >/dev/null 2>&1 || true
  ensure_no_macsimize
}

list_brave_windows() {
  python3 /Users/alex/.codex/skills/screenshot/scripts/take_screenshot.py --list-windows --app "$BRAVE_APP_NAME"
}

save_brave_windows() {
  local label="$1"
  local output
  output="$(artifact_path "$label" "txt")"
  list_brave_windows >"$output"
  printf '%s\n' "$output"
}

trigger_status_menu_item() {
  local title="$1"
  local alternate_title="$title"
  if [[ "$title" == "Maximize All" ]]; then
    alternate_title="Maximise All"
  elif [[ "$title" == "Maximise All" ]]; then
    alternate_title="Maximize All"
  fi

  osascript <<OSA >/dev/null
tell application "System Events"
  tell process "$APP_NAME"
    click menu bar item 1 of menu bar 2
    delay 0.35
    if exists menu item "$title" of menu 1 of menu bar item 1 of menu bar 2 then
      click menu item "$title" of menu 1 of menu bar item 1 of menu bar 2
      return
    end if
    if exists menu item "$alternate_title" of menu 1 of menu bar item 1 of menu bar 2 then
      click menu item "$alternate_title" of menu 1 of menu bar item 1 of menu bar 2
      return
    end if
    error "menu item not found"
  end tell
end tell
OSA
}

compare_restore_bounds() {
  local before_file="$1"
  local after_file="$2"
  python3 - "$before_file" "$after_file" "$BRAVE_MIN_WINDOWS" <<'PY'
import sys

def parse(path):
    result = {}
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) < 4:
                continue
            window_id = parts[0].strip()
            bounds = parts[-1].strip()
            result[window_id] = bounds
    return result

before = parse(sys.argv[1])
after = parse(sys.argv[2])
minimum = int(sys.argv[3])
common_ids = sorted(set(before) & set(after))

if len(common_ids) < minimum:
    print(f"expected at least {minimum} common Brave windows, found {len(common_ids)}", file=sys.stderr)
    sys.exit(1)

mismatches = [
    f"{window_id}: before={before[window_id]} after={after[window_id]}"
    for window_id in common_ids
    if before[window_id] != after[window_id]
]

if mismatches:
    print("\n".join(mismatches), file=sys.stderr)
    sys.exit(1)
PY
}

cleanup() {
  stop_macsimize
  ensure_no_other_macsimize_instances
}
trap cleanup EXIT

echo "== Macsimize Brave batch restore regression checks =="
run_test_preflight false
require_tool python3
resolve_app_paths
ensure_no_other_macsimize_instances

if ! process_running_by_bundle "$BRAVE_BUNDLE_ID"; then
  echo "error: $BRAVE_APP_NAME is not running." >&2
  exit 1
fi

init_artifact_dir "macsimize-brave-batch" >/dev/null
LOG_FILE="$(artifact_path "macsimize" "log")"
start_macsimize "$LOG_FILE"

BEFORE_WINDOWS="$(save_brave_windows "brave-before")"
capture_artifact_screenshot "brave-before" >/dev/null

trigger_status_menu_item "Maximise All"
sleep 1.2
MAX_WINDOWS="$(save_brave_windows "brave-after-maximise")"
capture_artifact_screenshot "brave-after-maximise" >/dev/null

trigger_status_menu_item "Restore All"
sleep 1.2
RESTORE_WINDOWS="$(save_brave_windows "brave-after-restore")"
capture_artifact_screenshot "brave-after-restore" >/dev/null

if compare_restore_bounds "$BEFORE_WINDOWS" "$RESTORE_WINDOWS"; then
  echo "PASS: Brave windows restored to exact original bounds"
else
  echo "FAIL: Brave restore bounds changed" >&2
  tail -n 120 "$LOG_FILE" >&2 || true
  exit 1
fi

printf 'Artifacts: %s\n' "$TEST_ARTIFACT_DIR"
printf 'Window snapshots: %s %s %s\n' "$BEFORE_WINDOWS" "$MAX_WINDOWS" "$RESTORE_WINDOWS"
