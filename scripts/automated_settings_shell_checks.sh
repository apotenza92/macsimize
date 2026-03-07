#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_common.sh"

run_test_preflight false

LOG_FILE="/tmp/macsimize-settings-shell.log"

cleanup() {
  stop_macsimize
  ensure_no_macsimize
}
trap cleanup EXIT

append_launch() {
  MACSIMIZE_DEBUG_LOG="${MACSIMIZE_DEBUG_LOG:-1}" \
  MACSIMIZE_TEST_SUITE=1 \
  MACSIMIZE_LOG_FILE="$LOG_FILE" \
  "$APP_BIN" "$@" >/dev/null 2>&1 &
  local launched_pid=$!
  disown "$launched_pid" >/dev/null 2>&1 || true
  sleep 1.0
}

count_log_occurrences() {
  local needle="$1"
  local file="$2"
  [[ -f "$file" ]] || {
    echo 0
    return 0
  }
  (grep -F "$needle" "$file" || true) | wc -l | awk '{print $1}'
}

wait_for_log_occurrence_count() {
  local needle="$1"
  local expected_minimum="$2"
  local file="$3"
  local timeout_seconds="${4:-6}"
  local deadline=$((SECONDS + timeout_seconds))
  local current=0

  while (( SECONDS <= deadline )); do
    current="$(count_log_occurrences "$needle" "$file")"
    if (( current >= expected_minimum )); then
      echo "$current"
      return 0
    fi
    sleep 0.25
  done

  echo "$current"
  return 1
}

read_selected_action() {
  defaults read "$BUNDLE_ID" selectedAction 2>/dev/null || echo ""
}

wait_for_selected_action() {
  local expected="$1"
  local timeout_seconds="${2:-6}"
  local deadline=$((SECONDS + timeout_seconds))
  local current=""

  while (( SECONDS <= deadline )); do
    current="$(read_selected_action)"
    if [[ "$current" == "$expected" ]]; then
      echo "$current"
      return 0
    fi
    sleep 0.25
  done

  echo "$current"
  return 1
}

click_action_mode_radio() {
  local label="$1"
  /usr/bin/swift "$SCRIPT_DIR/ax_press_control.swift" "$APP_NAME" AXRadioButton "$label" >/dev/null
}

defaults delete "$BUNDLE_ID" selectedAction >/dev/null 2>&1 || true

echo "[settings-shell] direct --settings launch"
start_macsimize_for_settings_shell "$LOG_FILE" --settings
sleep 1.0
if ! log_contains "Launch argument requested settings window" "$LOG_FILE"; then
  echo "FAIL: missing settings launch-argument log"
  print_log_tail "$LOG_FILE" 80
  exit 1
fi
if ! log_contains "Opening settings window" "$LOG_FILE"; then
  echo "FAIL: missing settings open log after --settings launch"
  print_log_tail "$LOG_FILE" 80
  exit 1
fi
if ! log_contains "Settings window fronting pass completed" "$LOG_FILE"; then
  echo "FAIL: missing settings fronting log after --settings launch"
  print_log_tail "$LOG_FILE" 80
  exit 1
fi
if [[ "$(wait_for_selected_action maximize 4 || true)" != "maximize" ]]; then
  echo "FAIL: expected fresh settings launch to persist Maximize as the default action"
  print_log_tail "$LOG_FILE" 80
  exit 1
fi

echo "[settings-shell] action mode radio buttons should update the selected action"
click_action_mode_radio "Full Screen"
if [[ "$(wait_for_selected_action fullScreen 4 || true)" != "fullScreen" ]]; then
  echo "FAIL: expected clicking Full Screen to persist fullScreen"
  print_log_tail "$LOG_FILE" 80
  exit 1
fi
click_action_mode_radio "Maximize"
if [[ "$(wait_for_selected_action maximize 4 || true)" != "maximize" ]]; then
  echo "FAIL: expected clicking Maximize to persist maximize"
  print_log_tail "$LOG_FILE" 80
  exit 1
fi
assert_macsimize_alive "$LOG_FILE" "after action-mode radio button toggles"

echo "[settings-shell] repeated relaunch should still show settings"
base_opened="$(count_log_occurrences "Opening settings window" "$LOG_FILE")"
for round in 1 2 3 4 5; do
  append_launch --settings
  opened_now="$(wait_for_log_occurrence_count "Opening settings window" "$((base_opened + round))" "$LOG_FILE" 8 || true)"
  if (( opened_now < base_opened + round )); then
    echo "FAIL: expected settings window open during round $round"
    print_log_tail "$LOG_FILE" 120
    exit 1
  fi
  echo "  round $round opens=$opened_now"
done

echo "[settings-shell] Finder-style relaunch should also show settings"
base_opened="$(count_log_occurrences "Opening settings window" "$LOG_FILE")"
append_launch -psn_0_12345
if [[ "$(wait_for_log_occurrence_count "Opening settings window" "$((base_opened + 1))" "$LOG_FILE" 8 || true)" -lt "$((base_opened + 1))" ]]; then
  echo "FAIL: expected Finder-style relaunch to open settings"
  print_log_tail "$LOG_FILE" 120
  exit 1
fi
if ! log_contains "Finder launch detected" "$LOG_FILE"; then
  echo "FAIL: missing Finder launch detection log"
  print_log_tail "$LOG_FILE" 120
  exit 1
fi

echo "== settings shell checks passed =="
