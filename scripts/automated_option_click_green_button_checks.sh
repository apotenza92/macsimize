#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_common.sh"

LOG_FILE="/tmp/macsimize-option-green-button.log"

run_test_preflight false

cleanup() {
  stop_macsimize
  ensure_no_macsimize
  close_textedit_windows
}
trap cleanup EXIT

bounds_meaningfully_changed() {
  local a="$1"
  local b="$2"
  local tolerance="${3:-60}"
  python3 - "$a" "$b" "$tolerance" <<'PY'
import sys
ax = [int(float(v)) for v in sys.argv[1].split(',')]
bx = [int(float(v)) for v in sys.argv[2].split(',')]
tol = int(sys.argv[3])
deltas = [abs(x - y) for x, y in zip(ax, bx)]
print("true" if max(deltas) >= tol else "false")
PY
}

wait_for_textedit_bounds_change() {
  local original="$1"
  local deadline=$((SECONDS + 12))

  while (( SECONDS <= deadline )); do
    local current
    current="$(textedit_front_window_bounds)"
    if [[ "$(bounds_meaningfully_changed "$current" "$original" 60)" == "true" ]]; then
      echo "$current"
      return 0
    fi
    sleep 0.3
  done

  textedit_front_window_bounds
  return 1
}

textedit_focused_window_full_screen() {
  /usr/bin/swift - <<'SWIFT' 2>/dev/null
import ApplicationServices
import AppKit
import Foundation

func boolAttr(_ element: AXUIElement, _ key: String) -> Bool? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success,
          let number = value as? NSNumber else {
        return nil
    }
    return number.boolValue
}

guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == "TextEdit" }) else {
    exit(1)
}

let appElement = AXUIElementCreateApplication(app.processIdentifier)
var focusedValue: CFTypeRef?
guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedValue) == .success,
      let focusedValue else {
    exit(1)
}

let window = unsafeBitCast(focusedValue, to: AXUIElement.self)
if let isFullScreen = boolAttr(window, "AXFullScreen") {
    print(isFullScreen ? "true" : "false")
}
SWIFT
}

wait_for_textedit_full_screen() {
  local expected="$1"
  local timeout_seconds="${2:-12}"
  local deadline=$((SECONDS + timeout_seconds))
  local current=""

  while (( SECONDS <= deadline )); do
    current="$(textedit_focused_window_full_screen || true)"
    if [[ "$current" == "$expected" ]]; then
      echo "$current"
      return 0
    fi
    sleep 0.3
  done

  echo "$current"
  return 1
}

option_click_green_button() {
  local attempt

  if [[ -z "${CLICLICK_BIN:-}" ]]; then
    resolve_cliclick_bin >/dev/null 2>&1 || true
  fi

  for attempt in 1 2 3 4 5; do
    open -a TextEdit >/dev/null 2>&1 || true
    sleep 0.6

    MACSIMIZE_CLICK_OPTION=1 /usr/bin/swift "$SCRIPT_DIR/click_window_green_button.swift" TextEdit && return 0

    if [[ -n "${CLICLICK_BIN:-}" ]]; then
      local click_point
      click_point="$(textedit_green_button_center || true)"
      if [[ -n "$click_point" ]]; then
        "$CLICLICK_BIN" "kd:alt" "c:$click_point" "ku:alt" && return 0
      fi
    fi

    sleep 1
  done
  return 1
}

echo "[option-green-button] configure Maximize mode"
write_pref_string selectedAction maximize
write_pref_bool diagnosticsEnabled true
write_pref_bool showSettingsOnStartup false
write_pref_bool firstLaunchCompleted true

start_macsimize "$LOG_FILE"
assert_macsimize_alive "$LOG_FILE" "startup in Maximize mode"

prepare_textedit_fixture
maximize_original_bounds="$(textedit_front_window_bounds)"
option_click_green_button
maximize_option_full_screen_state="$(wait_for_textedit_full_screen true 12 || true)"
assert_macsimize_alive "$LOG_FILE" "after Maximize-mode Option-click"
if [[ "$maximize_option_full_screen_state" != "true" ]]; then
  echo "FAIL: expected Option-click in Maximize mode to enter native macOS full screen"
  print_log_tail "$LOG_FILE" 120
  exit 1
fi
if ! log_contains "Triggered native macOS full screen via AXFullScreen on the window." "$LOG_FILE"; then
  echo "FAIL: missing direct full-screen diagnostics for Option-click in Maximize mode"
  print_log_tail "$LOG_FILE" 120
  exit 1
fi
echo "  maximize-mode Option-click entered full screen from bounds=$maximize_original_bounds"

echo "[option-green-button] configure Full Screen mode"
stop_macsimize
ensure_no_macsimize
: > "$LOG_FILE"
write_pref_string selectedAction fullScreen
write_pref_bool diagnosticsEnabled true
write_pref_bool showSettingsOnStartup false
write_pref_bool firstLaunchCompleted true

start_macsimize "$LOG_FILE"
assert_macsimize_alive "$LOG_FILE" "startup in Full Screen mode"

prepare_textedit_fixture
full_screen_original_bounds="$(textedit_front_window_bounds)"
option_click_green_button
full_screen_option_changed_bounds="$(wait_for_textedit_bounds_change "$full_screen_original_bounds" || true)"
full_screen_option_state="$(textedit_focused_window_full_screen || true)"
assert_macsimize_alive "$LOG_FILE" "after Full Screen-mode Option-click"
if [[ -z "$full_screen_option_changed_bounds" || "$(bounds_meaningfully_changed "$full_screen_option_changed_bounds" "$full_screen_original_bounds" 60)" != "true" ]]; then
  echo "FAIL: expected Option-click in Full Screen mode to maximize the TextEdit window"
  print_log_tail "$LOG_FILE" 120
  exit 1
fi
if [[ "$full_screen_option_state" == "true" ]]; then
  echo "FAIL: expected Option-click in Full Screen mode to stay out of native macOS full screen"
  print_log_tail "$LOG_FILE" 120
  exit 1
fi
if ! log_contains "Deterministic maximize applied" "$LOG_FILE"; then
  echo "FAIL: missing maximize diagnostics for Option-click in Full Screen mode"
  print_log_tail "$LOG_FILE" 120
  exit 1
fi
echo "  full-screen-mode Option-click maximized to bounds=$full_screen_option_changed_bounds"

echo "== option-click green button opposite-behavior automation passed =="
