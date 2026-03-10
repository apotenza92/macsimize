#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_common.sh"

# Guided multi-Space regression harness for current-Space-only batch maximize,
# titlebar double-click maximize, and drag-restore behavior.
#
# Required layout before running:
#   Desktop 1: control space; Finder can be activated here.
#   Desktop 2: target app window A.
#   Desktop 3: target app window B.
#
# Defaults target TextEdit because it has a standard titlebar and is easy to
# set up with multiple document windows in separate Spaces.
#
# The harness automates everything it can reliably reach from shell tooling,
# then falls back to explicit operator prompts for the menu bar path or any
# titlebar interaction that Accessibility refuses to drive on the current setup.

: "${MULTI_SPACE_TARGET_APP:=TextEdit}"
: "${MULTI_SPACE_TARGET_PROCESS:=TextEdit}"
: "${MULTI_SPACE_TARGET_BUNDLE:=com.apple.TextEdit}"
: "${MULTI_SPACE_CONTROL_SPACE:=1}"
: "${MULTI_SPACE_APP_SPACE_A:=2}"
: "${MULTI_SPACE_APP_SPACE_B:=3}"

LOG_FILE=""
PREF_BACKUP=""
ARTIFACT_NOTES=""
CHECKLIST_PATH=""
TOTAL_FAILURES=0

ensure_no_other_macsimize_instances() {
  pkill -x 'Macsimize Beta' >/dev/null 2>&1 || true
  pkill -f 'Macsimize Beta.app/Contents/MacOS/Macsimize Beta' >/dev/null 2>&1 || true
  ensure_no_macsimize
}

backup_preferences() {
  local output="$1"
  defaults export "$BUNDLE_ID" - >"$output" 2>/dev/null || true
}

restore_preferences() {
  local backup_file="$1"
  if [[ -s "$backup_file" ]]; then
    defaults import "$BUNDLE_ID" "$backup_file" >/dev/null 2>&1 || true
  fi
}

append_note() {
  local line="$1"
  printf '%s\n' "$line" >>"$ARTIFACT_NOTES"
}

wait_for_log_contains() {
  local needle="$1"
  local timeout_seconds="${2:-8}"
  local deadline=$((SECONDS + timeout_seconds))

  while (( SECONDS <= deadline )); do
    if log_contains "$needle" "$LOG_FILE"; then
      return 0
    fi
    sleep 0.2
  done

  return 1
}

scenario_pass() {
  local label="$1"
  echo "  PASS $label"
}

scenario_fail() {
  local label="$1"
  echo "  FAIL $label"
  append_note "failure=$label"
  TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
}

prompt_operator() {
  local prompt="$1"
  printf '%s\n' "$prompt"
  printf 'Press Return when complete... '
  read -r _
}

validate_multi_space_preconditions() {
  local spaces=(
    "$MULTI_SPACE_CONTROL_SPACE"
    "$MULTI_SPACE_APP_SPACE_A"
    "$MULTI_SPACE_APP_SPACE_B"
  )

  local space
  for space in "${spaces[@]}"; do
    if ! space_shortcut_enabled "$space"; then
      echo "error: Control+${space} must be enabled in Mission Control keyboard shortcuts before running this harness." >&2
      exit 1
    fi
  done

  if ! process_running_by_bundle "$MULTI_SPACE_TARGET_BUNDLE"; then
    echo "error: target bundle '$MULTI_SPACE_TARGET_BUNDLE' is not running." >&2
    echo "Create one '$MULTI_SPACE_TARGET_APP' window in Desktop $MULTI_SPACE_APP_SPACE_A and another in Desktop $MULTI_SPACE_APP_SPACE_B first." >&2
    exit 1
  fi
}

target_front_window_bounds() {
  osascript -e "tell application \"$MULTI_SPACE_TARGET_APP\" to get bounds of front window" \
    | tr -d '{}' \
    | awk -F',' '{gsub(/ /, ""); printf "%s,%s,%s,%s", $1, $2, $3, $4}'
}

target_titlebar_point() {
  local bounds
  bounds="$(target_front_window_bounds)"
  python3 - "$bounds" <<'PY'
import sys
left, top, right, bottom = [int(float(v)) for v in sys.argv[1].split(',')]
x = left + int((right - left) * 0.5)
y = top + 18
print(f"{x},{y}")
PY
}

target_drag_restore_destination() {
  local point="$1"
  python3 - "$point" <<'PY'
import sys
x, y = [int(float(v)) for v in sys.argv[1].split(',')]
print(f"{x + 220},{y + 120}")
PY
}

activate_target_app() {
  osascript -e "tell application \"$MULTI_SPACE_TARGET_APP\" to activate" >/dev/null 2>&1 || true
  sleep 0.8
}

try_trigger_status_menu_item() {
  local title="$1"
  local alternate_title="$title"
  if [[ "$title" == "Maximize All" ]]; then
    alternate_title="Maximise All"
  elif [[ "$title" == "Maximise All" ]]; then
    alternate_title="Maximize All"
  fi

  osascript <<OSA >/dev/null 2>&1
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

save_log_excerpt() {
  local label="$1"
  local output
  output="$(artifact_path "$label" "log")"
  tail -n 120 "$LOG_FILE" >"$output" 2>/dev/null || true
  printf '%s\n' "$output"
}

capture_space_snapshot() {
  local space="$1"
  local label="$2"

  switch_to_space "$space"
  sleep 0.5
  record_frontmost_snapshot "${label}-frontmost" >/dev/null
  capture_bundle_state_summary "$MULTI_SPACE_TARGET_BUNDLE" "$MULTI_SPACE_TARGET_PROCESS" "${label}-bundle" >/dev/null
  capture_process_ax_window_summary "$MULTI_SPACE_TARGET_PROCESS" "${label}-ax" >/dev/null
  capture_artifact_screenshot "${label}-screen" >/dev/null
}

write_manual_checklist() {
  local output
  output="$(artifact_path "MANUAL_CHECKLIST" "md")"
  cat >"$output" <<EOF
# Macsimize Multi-Space Manual Checklist

- Confirm Desktop ${MULTI_SPACE_CONTROL_SPACE} is a control Space and Desktops ${MULTI_SPACE_APP_SPACE_A}/${MULTI_SPACE_APP_SPACE_B} each contain a ${MULTI_SPACE_TARGET_APP} window.
- Run the \`Maximize All\` scenario from Desktop ${MULTI_SPACE_APP_SPACE_A} and confirm only that Space's eligible windows change.
- Switch to Desktop ${MULTI_SPACE_APP_SPACE_B} and confirm its window remains unchanged until \`Maximize All\` is triggered there.
- With Macsimize in maximize mode, double-click the ${MULTI_SPACE_TARGET_APP} titlebar and confirm it toggles Macsimize maximize/restore rather than native zoom/fill.
- With a Macsimize-managed maximized window, drag from the titlebar and confirm the window restores immediately and continues dragging.
- Repeat the titlebar double-click and drag-restore checks on another app with a unified toolbar, such as Safari or Finder.
- Repeat the localization checks with system English set to \`en\`, \`en-GB\`, and \`en-AU\`.
- Confirm menu labels, settings copy, help text, permission text, and \`Maximize All\`/\`Maximise All\` spelling are consistent with the system English variant.
- Review the captured log excerpts and confirm they distinguish titlebar double-click capture, drag-restore, batch maximize, and current-Space skip reasons.
EOF
  printf '%s\n' "$output"
}

scenario_batch_maximize() {
  echo "[scenario] current-Space Maximize All"
  capture_space_snapshot "$MULTI_SPACE_APP_SPACE_A" "maximize-all-before-space${MULTI_SPACE_APP_SPACE_A}"
  capture_space_snapshot "$MULTI_SPACE_APP_SPACE_B" "maximize-all-before-space${MULTI_SPACE_APP_SPACE_B}"
  switch_to_space "$MULTI_SPACE_APP_SPACE_A"
  activate_target_app

  if try_trigger_status_menu_item "Maximize All"; then
    scenario_pass "triggered menu bar Maximize All automatically"
  else
    prompt_operator "Trigger '$APP_NAME > Maximize All' on Desktop $MULTI_SPACE_APP_SPACE_A."
  fi

  sleep 1.2
  capture_space_snapshot "$MULTI_SPACE_APP_SPACE_A" "maximize-all-after-space${MULTI_SPACE_APP_SPACE_A}"
  capture_space_snapshot "$MULTI_SPACE_APP_SPACE_B" "maximize-all-after-space${MULTI_SPACE_APP_SPACE_B}"
  save_log_excerpt "maximize-all-log" >/dev/null

  if wait_for_log_contains "Menu bar requested batch maximize for current Space windows" 2 \
    || wait_for_log_contains "Batch maximize" 2 \
    || wait_for_log_contains "Batch maximise" 2; then
    scenario_pass "batch maximize logged"
  else
    scenario_fail "batch maximize log marker missing"
  fi
}

scenario_titlebar_double_click() {
  echo "[scenario] titlebar double-click maximize"
  switch_to_space "$MULTI_SPACE_APP_SPACE_A"
  activate_target_app
  capture_space_snapshot "$MULTI_SPACE_APP_SPACE_A" "titlebar-double-click-before"

  local point
  point="$(target_titlebar_point)"
  "$CLICLICK_BIN" -w 80 dc:"$point" >/dev/null 2>&1 || {
    prompt_operator "Double-click the ${MULTI_SPACE_TARGET_APP} titlebar in Desktop $MULTI_SPACE_APP_SPACE_A."
  }

  sleep 1.0
  capture_space_snapshot "$MULTI_SPACE_APP_SPACE_A" "titlebar-double-click-after"
  save_log_excerpt "titlebar-double-click-log" >/dev/null

  if wait_for_log_contains "Captured titlebar double-click" 2; then
    scenario_pass "titlebar double-click capture logged"
  else
    scenario_fail "titlebar double-click capture log missing"
  fi
}

scenario_drag_restore() {
  echo "[scenario] titlebar drag-restore"
  switch_to_space "$MULTI_SPACE_APP_SPACE_A"
  activate_target_app

  local start_point destination
  start_point="$(target_titlebar_point)"
  destination="$(target_drag_restore_destination "$start_point")"

  capture_space_snapshot "$MULTI_SPACE_APP_SPACE_A" "drag-restore-before"
  "$CLICLICK_BIN" -w 100 dd:"$start_point" dm:"$destination" du:"$destination" >/dev/null 2>&1 || {
    prompt_operator "Drag the ${MULTI_SPACE_TARGET_APP} titlebar away from its maximized state in Desktop $MULTI_SPACE_APP_SPACE_A."
  }

  sleep 1.0
  capture_space_snapshot "$MULTI_SPACE_APP_SPACE_A" "drag-restore-after"
  save_log_excerpt "drag-restore-log" >/dev/null

  if wait_for_log_contains "Triggered drag-restore" 2; then
    scenario_pass "drag-restore log marker observed"
  else
    scenario_fail "drag-restore log marker missing"
  fi
}

cleanup() {
  stop_macsimize
  ensure_no_other_macsimize_instances
  if [[ -n "${PREF_BACKUP:-}" ]]; then
    restore_preferences "$PREF_BACKUP"
  fi
}
trap cleanup EXIT

echo "== Macsimize multi-space regression checks =="
run_test_preflight true
validate_multi_space_preconditions
init_artifact_dir "macsimize-multi-space" >/dev/null

LOG_FILE="$(artifact_path "macsimize" "log")"
ARTIFACT_NOTES="$(artifact_path "NOTES" "txt")"
PREF_BACKUP="$(artifact_path "macsimize-preferences" "plist")"
CHECKLIST_PATH="$(write_manual_checklist)"
backup_preferences "$PREF_BACKUP"

append_note "artifact_dir=$TEST_ARTIFACT_DIR"
append_note "target_app=$MULTI_SPACE_TARGET_APP"
append_note "target_process=$MULTI_SPACE_TARGET_PROCESS"
append_note "target_bundle=$MULTI_SPACE_TARGET_BUNDLE"
append_note "control_space=$MULTI_SPACE_CONTROL_SPACE"
append_note "app_space_a=$MULTI_SPACE_APP_SPACE_A"
append_note "app_space_b=$MULTI_SPACE_APP_SPACE_B"

write_pref_string selectedAction maximize
write_pref_bool diagnosticsEnabled true
write_pref_bool showSettingsOnStartup false
write_pref_bool firstLaunchCompleted true

ensure_no_other_macsimize_instances
start_macsimize "$LOG_FILE"
assert_macsimize_alive "$LOG_FILE" "startup"

echo "artifacts: $TEST_ARTIFACT_DIR"
echo "manual checklist: $CHECKLIST_PATH"

scenario_batch_maximize
scenario_titlebar_double_click
scenario_drag_restore

echo
echo "log file: $LOG_FILE"
echo "artifact bundle: $TEST_ARTIFACT_DIR"

if (( TOTAL_FAILURES > 0 )); then
  echo "== multi-space regression checks complete with $TOTAL_FAILURES failure(s) =="
  exit 1
fi

echo "== multi-space regression checks complete =="
