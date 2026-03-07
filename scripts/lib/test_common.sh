#!/usr/bin/env bash

: "${BUNDLE_ID:=com.example.Macsimize}"
: "${APP_NAME:=Macsimize}"
: "${MACSIMIZE_START_TIMEOUT_SECONDS:=12}"
: "${MACSIMIZE_READY_LOG_MARKER:=Event tap started.}"

APP_BIN="${APP_BIN:-}"
APP_BUNDLE="${APP_BUNDLE:-}"
CLICLICK_BIN="${CLICLICK_BIN:-}"

APP_PID=""
START_MACSIMIZE_LAST_ERROR=""

log_contains() {
  local needle="$1"
  local file="$2"
  [[ -f "$file" ]] && grep -Fq "$needle" "$file"
}

print_log_tail() {
  local file="$1"
  local lines="${2:-40}"
  if [[ -f "$file" ]]; then
    echo "---- last ${lines} lines of $file ----"
    tail -n "$lines" "$file"
    echo "---- end log ----"
  else
    echo "(log file missing: $file)"
  fi
}

require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: required tool '$tool' was not found in PATH" >&2
    return 1
  fi
}

discover_latest_debug_app_bundle() {
  local derived_data_root="$HOME/Library/Developer/Xcode/DerivedData"
  local repo_debug_bundle="$PWD/.build/Build/Products/Debug/${APP_NAME}.app"
  local -a candidates=()

  if [[ -d "$repo_debug_bundle" ]]; then
    candidates+=("$repo_debug_bundle")
  fi

  if [[ -d "$derived_data_root" ]]; then
    while IFS= read -r candidate; do
      candidates+=("$candidate")
    done < <(find "$derived_data_root" -type d -path "*/Build/Products/Debug/${APP_NAME}.app" 2>/dev/null)
  fi

  local latest_bundle=""
  local latest_mtime=-1
  local candidate
  for candidate in "${candidates[@]}"; do
    local bin="$candidate/Contents/MacOS/${APP_NAME}"
    [[ -x "$bin" ]] || continue

    local mtime
    mtime="$(stat -f %m "$bin" 2>/dev/null || echo 0)"
    [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=0

    if (( mtime > latest_mtime )); then
      latest_mtime="$mtime"
      latest_bundle="$candidate"
    elif (( mtime == latest_mtime )) && [[ "$candidate" > "$latest_bundle" ]]; then
      latest_bundle="$candidate"
    fi
  done

  [[ -n "$latest_bundle" ]] && printf '%s\n' "$latest_bundle"
}

resolve_app_paths() {
  if [[ -n "${APP_BIN:-}" ]]; then
    if [[ ! -x "$APP_BIN" ]]; then
      echo "error: APP_BIN override is not executable: $APP_BIN" >&2
      return 1
    fi
    if [[ -z "${APP_BUNDLE:-}" ]]; then
      APP_BUNDLE="$(cd "$(dirname "$APP_BIN")/../.." && pwd -P)"
    fi
  elif [[ -n "${APP_BUNDLE:-}" ]]; then
    if [[ ! -d "$APP_BUNDLE" ]]; then
      echo "error: APP_BUNDLE override does not exist: $APP_BUNDLE" >&2
      return 1
    fi
    APP_BUNDLE="$(cd "$APP_BUNDLE" && pwd -P)"
    APP_BIN="$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
  else
    local discovered_bundle
    discovered_bundle="$(discover_latest_debug_app_bundle || true)"
    if [[ -z "$discovered_bundle" ]]; then
      echo "error: unable to discover ${APP_NAME} Debug app bundle (set APP_BIN or APP_BUNDLE)" >&2
      return 1
    fi
    APP_BUNDLE="$discovered_bundle"
    APP_BIN="$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
  fi

  if [[ ! -x "$APP_BIN" ]]; then
    echo "error: app binary missing at $APP_BIN" >&2
    return 1
  fi

  if [[ -z "${APP_BUNDLE:-}" || ! -d "$APP_BUNDLE" ]]; then
    echo "error: app bundle missing at $APP_BUNDLE" >&2
    return 1
  fi

  return 0
}

resolve_cliclick_bin() {
  if [[ -n "${CLICLICK_BIN:-}" ]]; then
    if [[ ! -x "$CLICLICK_BIN" ]]; then
      echo "error: CLICLICK_BIN override is not executable: $CLICLICK_BIN" >&2
      return 1
    fi
    return 0
  fi

  local discovered
  discovered="$(command -v cliclick || true)"
  if [[ -z "$discovered" ]]; then
    echo "error: cliclick not found (set CLICLICK_BIN or install cliclick)" >&2
    return 1
  fi
  CLICLICK_BIN="$discovered"
}

run_test_preflight() {
  local needs_cliclick="${1:-false}"
  require_tool osascript
  require_tool defaults
  require_tool grep
  require_tool awk
  require_tool sed
  require_tool open
  resolve_app_paths

  if [[ "$needs_cliclick" == "true" ]]; then
    resolve_cliclick_bin
  fi
}

macsimize_startup_failure_reason_from_log() {
  local log_file="$1"

  if log_contains "Event tap started." "$log_file"; then
    return 1
  fi
  if log_contains "startIfPossible: denied (no accessibility)." "$log_file"; then
    printf '%s\n' "accessibility permission denied"
    return 0
  fi
  if log_contains "startIfPossible: denied (no input monitoring)." "$log_file"; then
    printf '%s\n' "input monitoring permission denied"
    return 0
  fi
  if log_contains "Failed to start event tap." "$log_file"; then
    printf '%s\n' "event tap failed to start"
    return 0
  fi

  return 1
}

wait_for_macsimize_ready() {
  local log_file="$1"
  local timeout_seconds="${2:-$MACSIMIZE_START_TIMEOUT_SECONDS}"
  local deadline=$((SECONDS + timeout_seconds))
  START_MACSIMIZE_LAST_ERROR=""

  while (( SECONDS <= deadline )); do
    local startup_error
    startup_error="$(macsimize_startup_failure_reason_from_log "$log_file" || true)"
    if [[ -n "$startup_error" ]]; then
      START_MACSIMIZE_LAST_ERROR="$startup_error"
      return 1
    fi

    if log_contains "$MACSIMIZE_READY_LOG_MARKER" "$log_file"; then
      return 0
    fi

    if [[ -z "${APP_PID:-}" ]] || ! kill -0 "$APP_PID" >/dev/null 2>&1; then
      START_MACSIMIZE_LAST_ERROR="process exited before readiness marker '$MACSIMIZE_READY_LOG_MARKER'"
      return 1
    fi

    sleep 0.2
  done

  START_MACSIMIZE_LAST_ERROR="timed out after ${timeout_seconds}s waiting for '$MACSIMIZE_READY_LOG_MARKER'"
  return 1
}

wait_for_macsimize_launch() {
  local log_file="$1"
  local timeout_seconds="${2:-8}"
  local deadline=$((SECONDS + timeout_seconds))

  while (( SECONDS <= deadline )); do
    if log_contains "Launched bundle at" "$log_file"; then
      return 0
    fi

    if [[ -z "${APP_PID:-}" ]] || ! kill -0 "$APP_PID" >/dev/null 2>&1; then
      return 1
    fi

    sleep 0.2
  done

  return 1
}

ensure_no_macsimize() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  if [[ -n "${APP_BIN:-}" ]]; then
    pkill -f "$APP_BIN" >/dev/null 2>&1 || true
  else
    pkill -f "/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1 || true
  fi
}

start_macsimize() {
  local log_file="$1"
  shift

  stop_macsimize
  ensure_no_macsimize
  : > "$log_file"

  MACSIMIZE_DEBUG_LOG="${MACSIMIZE_DEBUG_LOG:-1}" \
  MACSIMIZE_TEST_SUITE=1 \
  MACSIMIZE_LOG_FILE="$log_file" \
  "$APP_BIN" "$@" >/dev/null 2>&1 &
  APP_PID=$!

  if ! wait_for_macsimize_ready "$log_file"; then
    echo "error: ${APP_NAME} failed to become ready: ${START_MACSIMIZE_LAST_ERROR:-unknown startup failure}" >&2
    print_log_tail "$log_file" 80 >&2
    stop_macsimize
    return 1
  fi
}

start_macsimize_for_settings_shell() {
  local log_file="$1"
  shift

  stop_macsimize
  ensure_no_macsimize
  : > "$log_file"

  MACSIMIZE_DEBUG_LOG="${MACSIMIZE_DEBUG_LOG:-1}" \
  MACSIMIZE_TEST_SUITE=1 \
  MACSIMIZE_LOG_FILE="$log_file" \
  "$APP_BIN" "$@" >/dev/null 2>&1 &
  APP_PID=$!

  if ! wait_for_macsimize_launch "$log_file"; then
    echo "error: ${APP_NAME} failed to launch for settings shell checks" >&2
    print_log_tail "$log_file" 80 >&2
    stop_macsimize
    return 1
  fi
}

stop_macsimize() {
  if [[ -n "${APP_PID:-}" ]]; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" >/dev/null 2>&1 || true
    APP_PID=""
  fi
}

assert_macsimize_alive() {
  local log_file="${1:-}"
  local context="${2:-${APP_NAME} process}"

  if [[ -z "${APP_PID:-}" ]] || ! kill -0 "$APP_PID" >/dev/null 2>&1; then
    echo "FAIL: $context exited unexpectedly" >&2
    [[ -n "$log_file" ]] && print_log_tail "$log_file" 80 >&2
    return 1
  fi

  return 0
}

frontmost_process() {
  osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || echo "unknown"
}

process_window_count() {
  local process_name="$1"
  osascript -e "tell application \"System Events\" to tell process \"$process_name\" to get count of windows" 2>/dev/null || echo 0
}

wait_for_process_window_min_count() {
  local process_name="$1"
  local minimum="$2"
  local timeout_seconds="${3:-8}"
  local deadline=$((SECONDS + timeout_seconds))
  local current=0

  while (( SECONDS <= deadline )); do
    current="$(process_window_count "$process_name")"
    [[ "$current" =~ ^[0-9]+$ ]] || current=0
    if (( current >= minimum )); then
      echo "$current"
      return 0
    fi
    sleep 0.25
  done

  echo "$current"
  return 1
}

write_pref_string() {
  local key="$1"
  local value="$2"
  defaults write "$BUNDLE_ID" "$key" -string "$value"
}

write_pref_bool() {
  local key="$1"
  local value="$2"
  defaults write "$BUNDLE_ID" "$key" -bool "$value"
}

close_textedit_windows() {
  osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
try
  tell application "TextEdit"
    quit saving no
  end tell
end try
APPLESCRIPT
  sleep 0.5
}

prepare_textedit_fixture() {
  close_textedit_windows

  osascript <<'APPLESCRIPT' >/dev/null
 tell application "TextEdit"
   activate
   make new document
   repeat 20 times
     if (count of windows) ≥ 1 then
       exit repeat
     end if
     delay 0.15
   end repeat
   set bounds of front window to {160, 160, 900, 700}
 end tell
APPLESCRIPT

  osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
 tell application "System Events"
   tell process "TextEdit"
     if exists sheet 1 of window 1 then
       try
         click button "Don’t Save" of sheet 1 of window 1
       end try
     end if
   end tell
 end tell
APPLESCRIPT

  sleep 1.0
}

textedit_front_window_bounds() {
  osascript -e 'tell application "TextEdit" to get bounds of front window' \
    | tr -d '{}' \
    | awk -F',' '{gsub(/ /, ""); printf "%s,%s,%s,%s", $1, $2, $3, $4}'
}

textedit_green_button_center() {
  local bounds
  bounds="$(textedit_front_window_bounds)"
  python3 - "$bounds" <<'PY'
import sys
left, top, right, bottom = [int(float(v)) for v in sys.argv[1].split(',')]
print(f"{left + 52},{top + 16}")
PY
}

click_textedit_green_button() {
  "$CLICLICK_BIN" c:"$(textedit_green_button_center)"
}
