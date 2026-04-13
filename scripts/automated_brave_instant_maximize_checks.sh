#!/usr/bin/env bash
set -euo pipefail

: "${APP_NAME:=Macsimize Dev}"
: "${BUNDLE_ID:=pzc.Macsimize.dev}"
: "${BRAVE_APP_NAME:=Brave Browser}"
: "${BRAVE_BUNDLE_ID:=com.brave.Browser}"
: "${BRAVE_RUN_COUNT:=3}"
: "${BRAVE_TRACE_DURATION_SECONDS:=2.4}"
: "${BRAVE_TRACE_INTERVAL_SECONDS:=0.016}"
: "${BRAVE_TRACE_TOLERANCE:=8}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_common.sh"

LOG_FILE=""
ERR_FILE=""
BRAVE_TEST_WINDOW_ID=""
APP_PID=""

start_stable_macsimize() {
  : > "$LOG_FILE"
  : > "$ERR_FILE"
  MACSIMIZE_LOG_FILE="$LOG_FILE" MACSIMIZE_ERR_FILE="$ERR_FILE" "$SCRIPT_DIR/run_stable_dev.sh" >/dev/null
  APP_PID="$(pgrep -f "$HOME/Applications/${APP_NAME}.app/Contents/MacOS/" | tail -n 1 || true)"
  if [[ -z "$APP_PID" ]]; then
    echo "error: could not find running $APP_NAME pid after stable launch" >&2
    print_log_tail "$LOG_FILE" 80 >&2
    return 1
  fi
}

stop_stable_macsimize() {
  "$SCRIPT_DIR/stop_running_macsimize.sh" >/dev/null 2>&1 || true
  APP_PID=""
}

cleanup() {
  close_brave_test_window
  stop_stable_macsimize
}
trap cleanup EXIT

ensure_brave_running() {
  if process_running_by_bundle "$BRAVE_BUNDLE_ID"; then
    return 0
  fi

  open -a "$BRAVE_APP_NAME" >/dev/null 2>&1 || true
  local deadline=$((SECONDS + 15))
  while (( SECONDS <= deadline )); do
    if process_running_by_bundle "$BRAVE_BUNDLE_ID"; then
      return 0
    fi
    sleep 0.3
  done

  echo "error: $BRAVE_APP_NAME did not launch" >&2
  return 1
}

create_brave_test_window() {
  close_brave_test_window

  BRAVE_TEST_WINDOW_ID="$(osascript <<'APPLESCRIPT'
tell application "Brave Browser"
  activate
  if (count of windows) = 0 then
    make new window
    delay 0.2
  end if
  make new window
  set bounds of front window to {160, 160, 1424, 1059}
  return (id of front window) as string
end tell
APPLESCRIPT
)"

  osascript -e 'tell application "Brave Browser" to activate' >/dev/null 2>&1 || true
  sleep 1.4
}

close_brave_test_window() {
  if [[ -z "${BRAVE_TEST_WINDOW_ID:-}" ]]; then
    return 0
  fi

  osascript <<APPLESCRIPT >/dev/null 2>&1 || true
tell application "Brave Browser"
  if (exists (first window whose id is ${BRAVE_TEST_WINDOW_ID})) then
    close (first window whose id is ${BRAVE_TEST_WINDOW_ID})
  end if
end tell
APPLESCRIPT

  BRAVE_TEST_WINDOW_ID=""
  sleep 0.4
}

trace_result_value() {
  local json_file="$1"
  local key="$2"
  python3 - "$json_file" "$key" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as fh:
    data = json.load(fh)
value = data[sys.argv[2]]
if isinstance(value, bool):
    print('true' if value else 'false')
elif value is None:
    print('')
else:
    print(value)
PY
}

trace_distinct_frame_count() {
  local json_file="$1"
  python3 - "$json_file" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as fh:
    data = json.load(fh)
print(len(data.get('distinctFrames', [])))
PY
}

print_trace_summary() {
  local json_file="$1"
  python3 - "$json_file" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as fh:
    data = json.load(fh)
print(f"  before={data['windowFrameBeforeClick']}")
print(f"  expected={data['expectedMaximizedFrame']}")
print(f"  final={data['finalFrame']}")
print(f"  distinctFrames={len(data.get('distinctFrames', []))}")
for sample in data.get('distinctFrames', []):
    print(f"    t={sample['elapsedMilliseconds']}ms frame={sample['frame']}")
if data.get('failureReason'):
    print(f"  failureReason={data['failureReason']}")
PY
}

echo "== Brave instant maximise regression checks =="
run_test_preflight false
require_tool python3
ensure_brave_running

init_artifact_dir "macsimize-brave-instant" >/dev/null
LOG_FILE="$(artifact_path "macsimize" "log")"
ERR_FILE="$(artifact_path "macsimize-stderr" "log")"

write_pref_string selectedAction maximize
write_pref_bool diagnosticsEnabled true
write_pref_bool showSettingsOnStartup false
write_pref_bool firstLaunchCompleted true

start_stable_macsimize
assert_macsimize_alive "$LOG_FILE" "startup"

pass_count=0
for run in $(seq 1 "$BRAVE_RUN_COUNT"); do
  echo "-- run $run/$BRAVE_RUN_COUNT --"
  create_brave_test_window
  local_json="$(artifact_path "brave-trace-run-${run}" "json")"
  local_stderr="$(artifact_path "brave-trace-run-${run}-stderr" "log")"

  set +e
  MACSIMIZE_TRACE_DURATION_SECONDS="$BRAVE_TRACE_DURATION_SECONDS" \
  MACSIMIZE_TRACE_INTERVAL_SECONDS="$BRAVE_TRACE_INTERVAL_SECONDS" \
  MACSIMIZE_TRACE_TOLERANCE="$BRAVE_TRACE_TOLERANCE" \
  /usr/bin/swift "$SCRIPT_DIR/trace_green_button_transition.swift" "$BRAVE_APP_NAME" >"$local_json" 2>"$local_stderr"
  status=$?
  set -e

  if [[ -s "$local_json" ]]; then
    print_trace_summary "$local_json"
  fi
  capture_artifact_screenshot "brave-trace-run-${run}" >/dev/null || true
  assert_macsimize_alive "$LOG_FILE" "after Brave trace run $run"

  if [[ $status -eq 0 ]]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: Brave did not maximise in a single visible step on run $run" >&2
    if [[ -s "$local_stderr" ]]; then
      echo "---- trace helper stderr ----" >&2
      cat "$local_stderr" >&2
      echo "---- end trace helper stderr ----" >&2
    fi
    print_log_tail "$LOG_FILE" 160 >&2
    echo "Artifacts: $TEST_ARTIFACT_DIR" >&2
    exit 1
  fi

  close_brave_test_window
  sleep 0.6
 done

echo "PASS: Brave maximised instantly in $pass_count/$BRAVE_RUN_COUNT runs"
echo "Artifacts: $TEST_ARTIFACT_DIR"
