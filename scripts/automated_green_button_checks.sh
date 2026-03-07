#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_common.sh"

LOG_FILE="/tmp/macsimize-green-button.log"

run_test_preflight true

cleanup() {
  stop_macsimize
  ensure_no_macsimize
  close_textedit_windows
}
trap cleanup EXIT

bounds_nearly_equal() {
  local a="$1"
  local b="$2"
  local tolerance="${3:-40}"
  python3 - "$a" "$b" "$tolerance" <<'PY'
import sys
ax = [int(float(v)) for v in sys.argv[1].split(',')]
bx = [int(float(v)) for v in sys.argv[2].split(',')]
tol = int(sys.argv[3])
print("true" if all(abs(x - y) <= tol for x, y in zip(ax, bx)) else "false")
PY
}

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
  local mode="$2"
  local deadline=$((SECONDS + 12))

  while (( SECONDS <= deadline )); do
    local current
    current="$(textedit_front_window_bounds)"

    if [[ "$mode" == "change" ]]; then
      if [[ "$(bounds_meaningfully_changed "$current" "$original" 60)" == "true" ]]; then
        echo "$current"
        return 0
      fi
    else
      if [[ "$(bounds_nearly_equal "$current" "$original" 50)" == "true" ]]; then
        echo "$current"
        return 0
      fi
    fi

    sleep 0.3
  done

  textedit_front_window_bounds
  return 1
}

expected_maximized_bounds_for_window() {
  local window_bounds="$1"
  /usr/bin/swift -e '
import AppKit
import Foundation

func parseBounds(_ raw: String) -> CGRect {
    let values = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard values.count == 4 else { return .zero }
    return CGRect(x: values[0], y: values[1], width: values[2] - values[0], height: values[3] - values[1])
}

func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
    let rect = lhs.intersection(rhs)
    return rect.isNull ? 0 : rect.width * rect.height
}

func distanceSquared(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
    let dx = lhs.x - rhs.x
    let dy = lhs.y - rhs.y
    return dx * dx + dy * dy
}

let windowFrame = parseBounds(CommandLine.arguments[1])
let screens = NSScreen.screens
let desktopTop = screens.map { $0.frame.maxY }.max() ?? 0

let chosenScreen = screens.max {
    let lhsArea = intersectionArea(windowFrame, $0.frame)
    let rhsArea = intersectionArea(windowFrame, $1.frame)
    if lhsArea == rhsArea {
        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        let lhsDistance = distanceSquared(center, CGPoint(x: $0.frame.midX, y: $0.frame.midY))
        let rhsDistance = distanceSquared(center, CGPoint(x: $1.frame.midX, y: $1.frame.midY))
        return lhsDistance > rhsDistance
    }
    return lhsArea < rhsArea
} ?? NSScreen.main

if let screen = chosenScreen {
    let visible = screen.visibleFrame
    let x = Int(round(visible.minX))
    let y = Int(round(desktopTop - visible.maxY))
    let width = Int(round(visible.width))
    let height = Int(round(visible.height))
    print("\(x),\(y),\(x + width),\(y + height)")
}
' "$window_bounds"
}

echo "[green-button] configure Maximize mode"
write_pref_string selectedAction maximize
write_pref_bool diagnosticsEnabled true
write_pref_bool showSettingsOnStartup false
write_pref_bool firstLaunchCompleted true

start_macsimize "$LOG_FILE"
assert_macsimize_alive "$LOG_FILE" "startup"

prepare_textedit_fixture
original_bounds="$(textedit_front_window_bounds)"
expected_maximized_bounds="$(expected_maximized_bounds_for_window "$original_bounds")"
echo "  original bounds=$original_bounds"
echo "  expected maximized bounds=$expected_maximized_bounds"

click_textedit_green_button
changed_bounds="$(wait_for_textedit_bounds_change "$original_bounds" change || true)"
assert_macsimize_alive "$LOG_FILE" "after first green-button click"
screencapture -x /tmp/macsimize-green-button-after-maximize.png

echo "  changed bounds=$changed_bounds"
if [[ -z "$changed_bounds" || "$(bounds_meaningfully_changed "$changed_bounds" "$original_bounds" 60)" != "true" ]]; then
  echo "FAIL: expected first green-button click to maximize the TextEdit window meaningfully"
  print_log_tail "$LOG_FILE" 120
  exit 1
fi
if [[ "$(bounds_nearly_equal "$changed_bounds" "$expected_maximized_bounds" 8)" != "true" ]]; then
  echo "FAIL: expected maximized window bounds to match the usable screen frame"
  echo "  screenshot=/tmp/macsimize-green-button-after-maximize.png"
  print_log_tail "$LOG_FILE" 120
  exit 1
fi

click_textedit_green_button
restored_bounds="$(wait_for_textedit_bounds_change "$original_bounds" restore || true)"
assert_macsimize_alive "$LOG_FILE" "after second green-button click"
echo "  restored bounds=$restored_bounds"
if [[ -z "$restored_bounds" || "$(bounds_nearly_equal "$restored_bounds" "$original_bounds" 50)" != "true" ]]; then
  echo "FAIL: expected second green-button click to restore near the original bounds"
  print_log_tail "$LOG_FILE" 120
  exit 1
fi

if ! log_contains "Deterministic maximize" "$LOG_FILE"; then
  echo "FAIL: missing maximize diagnostics"
  print_log_tail "$LOG_FILE" 120
  exit 1
fi

echo "== green button maximize automation passed =="
