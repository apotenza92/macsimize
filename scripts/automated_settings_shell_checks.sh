#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_common.sh"

run_test_preflight false

LOG_FILE="/tmp/macsimize-settings-shell.log"
AX_PRESS_CONTROL_BIN="/tmp/macsimize-ax-press-control"

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

read_show_settings_on_startup() {
  defaults read "$BUNDLE_ID" showSettingsOnStartup 2>/dev/null || echo ""
}

read_update_check_frequency() {
  defaults read "$BUNDLE_ID" updateCheckFrequency 2>/dev/null || echo ""
}

preferred_maximize_label() {
  local locale
  locale="$(defaults read -g AppleLocale 2>/dev/null || echo "")"
  case "$locale" in
    en_GB*|en_AU*)
      echo "Maximise"
      ;;
    *)
      echo "Maximize"
      ;;
  esac
}

wait_for_default_value() {
  local read_command="$1"
  local expected="$2"
  local timeout_seconds="${3:-6}"
  local deadline=$((SECONDS + timeout_seconds))
  local current=""

  while (( SECONDS <= deadline )); do
    current="$($read_command)"
    if [[ "$current" == "$expected" ]]; then
      echo "$current"
      return 0
    fi
    sleep 0.25
  done

  echo "$current"
  return 1
}

wait_for_selected_action() {
  wait_for_default_value read_selected_action "$1" "${2:-6}"
}

wait_for_show_settings_on_startup() {
  wait_for_default_value read_show_settings_on_startup "$1" "${2:-6}"
}

wait_for_update_check_frequency() {
  wait_for_default_value read_update_check_frequency "$1" "${2:-6}"
}

select_settings_popup_item() {
  local popup_index="$1"
  local label="$2"
  if osascript <<APPLESCRIPT >/dev/null 2>&1
tell application "System Events"
  tell process "$APP_NAME"
    tell group 1 of window 1
      click pop up button $popup_index
      delay 0.2
      click menu item "$label" of menu 1 of pop up button $popup_index
    end tell
  end tell
end tell
APPLESCRIPT
  then
    return 0
  fi
  return 1
}

click_action_mode_button() {
  local label="$1"
  if select_settings_popup_item 1 "$label"; then
    return 0
  fi
  if [[ ! -x "$AX_PRESS_CONTROL_BIN" || "$SCRIPT_DIR/ax_press_control.swift" -nt "$AX_PRESS_CONTROL_BIN" ]]; then
    /usr/bin/swiftc "$SCRIPT_DIR/ax_press_control.swift" -o "$AX_PRESS_CONTROL_BIN"
  fi
  if "$AX_PRESS_CONTROL_BIN" "$APP_NAME" AXButton "$label" >/dev/null; then
    return 0
  fi
  "$AX_PRESS_CONTROL_BIN" "$APP_NAME" AXRadioButton "$label" >/dev/null
}

click_maximize_mode_button() {
  local preferred
  preferred="$(preferred_maximize_label)"
  local alternate="Maximize"
  if [[ "$preferred" == "Maximize" ]]; then
    alternate="Maximise"
  fi

  if click_action_mode_button "$preferred"; then
    return 0
  fi

  click_action_mode_button "$alternate"
}

click_show_settings_on_startup_checkbox() {
  osascript <<APPLESCRIPT >/dev/null
tell application "System Events"
  tell process "$APP_NAME"
    tell group 1 of window 1
      click checkbox 1
    end tell
  end tell
end tell
APPLESCRIPT
}

select_update_frequency() {
  local label="$1"
  select_settings_popup_item 2 "$label"
}

defaults delete "$BUNDLE_ID" selectedAction >/dev/null 2>&1 || true
defaults write "$BUNDLE_ID" showSettingsOnStartup -bool false
defaults write "$BUNDLE_ID" updateCheckFrequency -string daily

echo "[settings-shell] direct --settings launch"
start_macsimize_for_settings_shell "$LOG_FILE" --settings
sleep 1.0
if [[ "$(wait_for_log_occurrence_count "Launch argument requested settings window" 1 "$LOG_FILE" 6 || true)" -lt 1 ]]; then
  echo "FAIL: missing settings launch-argument log"
  print_log_tail "$LOG_FILE" 80
  exit 1
fi
if [[ "$(wait_for_log_occurrence_count "Opening settings window" 1 "$LOG_FILE" 6 || true)" -lt 1 ]]; then
  echo "FAIL: missing settings open log after --settings launch"
  print_log_tail "$LOG_FILE" 80
  exit 1
fi
if [[ "$(wait_for_log_occurrence_count "Settings window fronting pass completed" 1 "$LOG_FILE" 6 || true)" -lt 1 ]]; then
  echo "FAIL: missing settings fronting log after --settings launch"
  print_log_tail "$LOG_FILE" 80
  exit 1
fi
if [[ "$(wait_for_selected_action maximize 4 || true)" != "maximize" ]]; then
  echo "FAIL: expected fresh settings launch to persist Maximize as the default action"
  print_log_tail "$LOG_FILE" 80
  exit 1
fi

echo "[settings-shell] general checkbox should persist changes"
click_show_settings_on_startup_checkbox
if [[ "$(wait_for_show_settings_on_startup 1 4 || true)" != "1" ]]; then
  echo "FAIL: expected clicking Show settings on startup to persist true"
  print_log_tail "$LOG_FILE" 80
  exit 1
fi
click_show_settings_on_startup_checkbox
if [[ "$(wait_for_show_settings_on_startup 0 4 || true)" != "0" ]]; then
  echo "FAIL: expected clicking Show settings on startup again to persist false"
  print_log_tail "$LOG_FILE" 80
  exit 1
fi

echo "[settings-shell] action mode buttons should update the selected action"
click_action_mode_button "Full Screen"
if [[ "$(wait_for_selected_action fullScreen 4 || true)" != "fullScreen" ]]; then
  echo "FAIL: expected clicking Full Screen to persist fullScreen"
  print_log_tail "$LOG_FILE" 80
  exit 1
fi
click_maximize_mode_button
if [[ "$(wait_for_selected_action maximize 4 || true)" != "maximize" ]]; then
  echo "FAIL: expected clicking Maximize/Maximise to persist maximize"
  print_log_tail "$LOG_FILE" 80
  exit 1
fi

echo "[settings-shell] update frequency popup should persist changes"
select_update_frequency "Weekly"
if [[ "$(wait_for_update_check_frequency weekly 4 || true)" != "weekly" ]]; then
  echo "FAIL: expected selecting Weekly to persist weekly"
  print_log_tail "$LOG_FILE" 80
  exit 1
fi
select_update_frequency "Daily"
if [[ "$(wait_for_update_check_frequency daily 4 || true)" != "daily" ]]; then
  echo "FAIL: expected selecting Daily to persist daily"
  print_log_tail "$LOG_FILE" 80
  exit 1
fi

assert_macsimize_alive "$LOG_FILE" "after action-mode button toggles"

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
