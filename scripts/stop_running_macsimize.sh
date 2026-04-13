#!/bin/sh
set -eu

names='
Macsimize
Macsimize Beta
Macsimize Dev
'

paths='
/Macsimize.app/Contents/MacOS/Macsimize
/Macsimize Beta.app/Contents/MacOS/Macsimize Beta
/Macsimize Dev.app/Contents/MacOS/Macsimize Dev
'

list_matching_pids() {
  {
    printf '%s\n' "$names" | while IFS= read -r name; do
      [ -n "$name" ] || continue
      /usr/bin/pgrep -x "$name" 2>/dev/null || true
    done

    printf '%s\n' "$paths" | while IFS= read -r path; do
      [ -n "$path" ] || continue
      /usr/bin/pgrep -f "$path" 2>/dev/null || true
    done
  } | /usr/bin/awk 'NF { print }' | /usr/bin/sort -u
}

signal_matching_pids() {
  signal="$1"
  pids="$(list_matching_pids)"
  [ -n "$pids" ] || return 0

  printf '%s\n' "$pids" | while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    /bin/kill "-$signal" "$pid" 2>/dev/null || true
  done
}

wait_for_exit() {
  timeout="$1"
  elapsed=0

  while [ "$elapsed" -lt "$timeout" ]; do
    pids="$(list_matching_pids)"
    [ -z "$pids" ] && return 0
    /bin/sleep 1
    elapsed=$((elapsed + 1))
  done

  pids="$(list_matching_pids)"
  [ -z "$pids" ]
}

signal_matching_pids TERM
if wait_for_exit 4; then
  /bin/launchctl unsetenv MACSIMIZE_DEBUG_LOG 2>/dev/null || true
  /bin/launchctl unsetenv MACSIMIZE_LOG_FILE 2>/dev/null || true
  exit 0
fi

signal_matching_pids KILL
wait_for_exit 2 || true
/bin/launchctl unsetenv MACSIMIZE_DEBUG_LOG 2>/dev/null || true
/bin/launchctl unsetenv MACSIMIZE_LOG_FILE 2>/dev/null || true
