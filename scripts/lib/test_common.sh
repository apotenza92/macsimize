#!/usr/bin/env bash

: "${BUNDLE_ID:=pzc.Macsimize}"
: "${APP_NAME:=Macsimize}"
: "${MACSIMIZE_START_TIMEOUT_SECONDS:=12}"
: "${MACSIMIZE_READY_LOG_MARKER:=Event tap started.}"
: "${TEST_ARTIFACT_ROOT:=/tmp/macsimize-artifacts}"
: "${MULTI_SPACE_SWITCH_SETTLE_SECONDS:=0.9}"

APP_BIN="${APP_BIN:-}"
APP_BUNDLE="${APP_BUNDLE:-}"
CLICLICK_BIN="${CLICLICK_BIN:-}"

APP_PID=""
START_MACSIMIZE_LAST_ERROR=""
TEST_ARTIFACT_DIR=""

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
  require_tool plutil
  require_tool open
  require_tool screencapture
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

frontmost_bundle_id() {
  osascript -e 'tell application "System Events" to get bundle identifier of first process whose frontmost is true' 2>/dev/null || echo "unknown"
}

process_visible() {
  local process_name="$1"
  osascript -e "tell application \"System Events\" to get visible of process \"$process_name\"" 2>/dev/null || echo "missing"
}

process_name_for_bundle() {
  local bundle_identifier="$1"
  osascript -e "tell application \"System Events\" to get name of first process whose bundle identifier is \"$bundle_identifier\"" 2>/dev/null || true
}

process_bundle_id() {
  local process_name="$1"
  osascript -e "tell application \"System Events\" to get bundle identifier of process \"$process_name\"" 2>/dev/null || true
}

process_running_by_bundle() {
  local bundle_identifier="$1"
  local count
  count="$(osascript -e "tell application \"System Events\" to count (every process whose bundle identifier is \"$bundle_identifier\")" 2>/dev/null || echo 0)"
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  (( count > 0 ))
}

activate_finder() {
  osascript -e 'tell application "Finder" to activate' >/dev/null 2>&1 || true
  sleep 0.25
}

process_window_count() {
  local process_name="$1"
  osascript -e "tell application \"System Events\" to tell process \"$process_name\" to get count of windows" 2>/dev/null || echo 0
}

space_key_code() {
  local space_number="$1"
  case "$space_number" in
    1) printf '18\n' ;;
    2) printf '19\n' ;;
    3) printf '20\n' ;;
    4) printf '21\n' ;;
    5) printf '23\n' ;;
    6) printf '22\n' ;;
    7) printf '26\n' ;;
    8) printf '28\n' ;;
    9) printf '25\n' ;;
    *) echo "error: unsupported space number '$space_number' (expected 1-9)" >&2; return 1 ;;
  esac
}

space_symbolic_hotkey_id() {
  local space_number="$1"
  if [[ ! "$space_number" =~ ^[1-9]$ ]]; then
    echo "error: unsupported space number '$space_number' (expected 1-9)" >&2
    return 1
  fi
  printf '%s\n' "$((117 + space_number))"
}

space_shortcut_enabled() {
  local space_number="$1"
  local hotkey_id
  hotkey_id="$(space_symbolic_hotkey_id "$space_number")" || return 1
  local plist="$HOME/Library/Preferences/com.apple.symbolichotkeys.plist"
  if [[ ! -f "$plist" ]]; then
    return 1
  fi
  local enabled
  enabled="$(plutil -extract "AppleSymbolicHotKeys.$hotkey_id.enabled" raw -o - "$plist" 2>/dev/null || true)"
  [[ "$enabled" == "1" || "$enabled" == "true" ]]
}

switch_to_space() {
  local space_number="$1"
  local settle_seconds="${2:-$MULTI_SPACE_SWITCH_SETTLE_SECONDS}"
  local key_code
  key_code="$(space_key_code "$space_number")" || return 1
  osascript -e "tell application \"System Events\" to key code $key_code using control down" >/dev/null 2>&1 || return 1
  sleep "$settle_seconds"
}

init_artifact_dir() {
  local prefix="${1:-macsimize-artifacts}"
  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  TEST_ARTIFACT_DIR="${TEST_ARTIFACT_ROOT%/}/${prefix}-${stamp}"
  mkdir -p "$TEST_ARTIFACT_DIR"
  printf '%s\n' "$TEST_ARTIFACT_DIR"
}

artifact_path() {
  local label="$1"
  local extension="${2:-txt}"
  if [[ -z "${TEST_ARTIFACT_DIR:-}" ]]; then
    echo "error: TEST_ARTIFACT_DIR is not initialized" >&2
    return 1
  fi
  printf '%s/%s.%s\n' "$TEST_ARTIFACT_DIR" "$label" "$extension"
}

capture_artifact_screenshot() {
  local label="$1"
  local output
  output="$(artifact_path "$label" "png")" || return 1
  screencapture -x "$output"
  printf '%s\n' "$output"
}

record_frontmost_snapshot() {
  local label="$1"
  local output
  output="$(artifact_path "$label" "txt")" || return 1
  {
    printf 'timestamp=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'frontmost=%s\n' "$(frontmost_process)"
    printf 'frontmostBundle=%s\n' "$(frontmost_bundle_id)"
  } >"$output"
  printf '%s\n' "$output"
}

capture_process_ax_window_summary() {
  local process_name="$1"
  local label="$2"
  local output
  output="$(artifact_path "$label" "txt")" || return 1
  local bundle
  bundle="$(process_bundle_id "$process_name")"
  if [[ -z "$bundle" ]]; then
    {
      printf 'process=%s\n' "$process_name"
      printf 'missing=true\n'
    } >"$output"
    printf '%s\n' "$output"
    return 0
  fi

  local visible
  visible="$(process_visible "$process_name")"
  local window_count
  window_count="$(process_window_count "$process_name")"
  [[ "$window_count" =~ ^[0-9]+$ ]] || window_count=0

  local raw_titles raw_minimized raw_subroles
  raw_titles="$(osascript -e "tell application \"System Events\" to tell process \"$process_name\" to get name of every window" 2>/dev/null || true)"
  raw_minimized="$(osascript -e "tell application \"System Events\" to tell process \"$process_name\" to get value of attribute \"AXMinimized\" of every window" 2>/dev/null || true)"
  raw_subroles="$(osascript -e "tell application \"System Events\" to tell process \"$process_name\" to get value of attribute \"AXSubrole\" of every window" 2>/dev/null || true)"

  local -a title_items=()
  local -a minimized_items=()
  local -a subrole_items=()

  if [[ -n "$raw_titles" ]]; then
    IFS=',' read -r -a title_items <<<"$raw_titles"
  fi
  if [[ -n "$raw_minimized" ]]; then
    IFS=',' read -r -a minimized_items <<<"$raw_minimized"
  fi
  if [[ -n "$raw_subroles" ]]; then
    IFS=',' read -r -a subrole_items <<<"$raw_subroles"
  fi

  {
    printf 'process=%s\n' "$process_name"
    printf 'bundle=%s\n' "$bundle"
    printf 'visible=%s\n' "$visible"
    printf 'windowCount=%s\n' "$window_count"

    local index
    for ((index = 0; index < window_count; index++)); do
      local title="${title_items[$index]:-}"
      local minimized="${minimized_items[$index]:-missing}"
      local subrole="${subrole_items[$index]:-missing}"
      title="$(printf '%s' "$title" | sed 's/^ *//; s/ *$//')"
      minimized="$(printf '%s' "$minimized" | sed 's/^ *//; s/ *$//')"
      subrole="$(printf '%s' "$subrole" | sed 's/^ *//; s/ *$//')"
      printf 'window[%d].title=%s\n' "$((index + 1))" "$title"
      printf 'window[%d].minimized=%s\n' "$((index + 1))" "$minimized"
      printf 'window[%d].subrole=%s\n' "$((index + 1))" "$subrole"
    done
  } >"$output"
  printf '%s\n' "$output"
}

capture_bundle_state_summary() {
  local bundle_identifier="$1"
  local process_name_hint="$2"
  local label="$3"
  local output
  output="$(artifact_path "$label" "txt")" || return 1

  local running=false
  local process_name="$process_name_hint"
  local visible="missing"
  if process_running_by_bundle "$bundle_identifier"; then
    running=true
    if [[ -z "$process_name" ]]; then
      process_name="$(process_name_for_bundle "$bundle_identifier")"
    fi
    if [[ -n "$process_name" ]]; then
      visible="$(process_visible "$process_name")"
    fi
  fi

  local frontmost_bundle
  frontmost_bundle="$(frontmost_bundle_id)"
  local frontmost_name
  frontmost_name="$(frontmost_process)"
  local frontmost_matches=false
  if [[ "$frontmost_bundle" == "$bundle_identifier" ]]; then
    frontmost_matches=true
  fi

  {
    printf 'bundle=%s\n' "$bundle_identifier"
    printf 'process=%s\n' "$process_name"
    printf 'running=%s\n' "$running"
    printf 'visible=%s\n' "$visible"
    printf 'frontmostBundle=%s\n' "$frontmost_bundle"
    printf 'frontmostProcess=%s\n' "$frontmost_name"
    printf 'frontmostMatchesBundle=%s\n' "$frontmost_matches"
  } >"$output"

  printf '%s\n' "$output"
}

summary_state_value() {
  local file="$1"
  local key="$2"
  awk -F= -v target="$key" '$1 == target { print substr($0, index($0, "=") + 1); exit }' "$file"
}

summary_standard_window_count() {
  local file="$1"
  awk -F= '
    /^window\[[0-9]+\]\.subrole=AXStandardWindow$/ {
      count += 1
    }
    END {
      print count + 0
    }
  ' "$file"
}

summary_standard_window_minimized_count() {
  local file="$1"
  awk -F= '
    /^window\[[0-9]+\]\.subrole=/ {
      key = $1
      sub(/^window\[/, "", key)
      split(key, parts, /\]\./)
      subrole[parts[1]] = $2
    }
    /^window\[[0-9]+\]\.minimized=/ {
      key = $1
      sub(/^window\[/, "", key)
      split(key, parts, /\]\./)
      minimized[parts[1]] = $2
    }
    END {
      for (idx in subrole) {
        if (subrole[idx] == "AXStandardWindow" && minimized[idx] == "true") {
          count += 1
        }
      }
      print count + 0
    }
  ' "$file"
}

summary_standard_window_unminimized_count() {
  local file="$1"
  awk -F= '
    /^window\[[0-9]+\]\.subrole=/ {
      key = $1
      sub(/^window\[/, "", key)
      split(key, parts, /\]\./)
      subrole[parts[1]] = $2
    }
    /^window\[[0-9]+\]\.minimized=/ {
      key = $1
      sub(/^window\[/, "", key)
      split(key, parts, /\]\./)
      minimized[parts[1]] = $2
    }
    END {
      for (idx in subrole) {
        if (subrole[idx] == "AXStandardWindow" && minimized[idx] == "false") {
          count += 1
        }
      }
      print count + 0
    }
  ' "$file"
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
  local ax_bounds=""
  ax_bounds="$(
    /usr/bin/swift - <<'SWIFT' 2>/dev/null
import ApplicationServices
import AppKit
import Foundation

func pointAttr(_ element: AXUIElement, _ key: String) -> CGPoint? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success,
          let value else {
        return nil
    }

    let axValue = unsafeBitCast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cgPoint else {
        return nil
    }

    var point = CGPoint.zero
    guard AXValueGetValue(axValue, .cgPoint, &point) else {
        return nil
    }
    return point
}

func sizeAttr(_ element: AXUIElement, _ key: String) -> CGSize? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success,
          let value else {
        return nil
    }

    let axValue = unsafeBitCast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cgSize else {
        return nil
    }

    var size = CGSize.zero
    guard AXValueGetValue(axValue, .cgSize, &size) else {
        return nil
    }
    return size
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
guard let point = pointAttr(window, kAXPositionAttribute),
      let size = sizeAttr(window, kAXSizeAttribute) else {
    exit(1)
}

let left = Int(point.x.rounded())
let top = Int(point.y.rounded())
let right = Int((point.x + size.width).rounded())
let bottom = Int((point.y + size.height).rounded())
print("\(left),\(top),\(right),\(bottom)")
SWIFT
  )" || true

  if [[ -n "$ax_bounds" ]]; then
    printf '%s' "$ax_bounds"
    return 0
  fi

  local attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    local bounds_raw
    bounds_raw="$(osascript -e 'tell application "TextEdit" to get bounds of front window' 2>/dev/null || true)"
    if [[ -n "$bounds_raw" ]]; then
      printf '%s' "$bounds_raw" | tr -d '{}' | awk -F',' '{gsub(/ /, ""); printf "%s,%s,%s,%s", $1, $2, $3, $4}'
      return 0
    fi
    sleep 0.2
  done

  return 1
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
