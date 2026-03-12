#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/test_common.sh"

MATRIX_PATH="$REPO_ROOT/Tests/titlebar_app_matrix.csv"
FILTER_FAMILY=""
FILTER_PRIORITY=""
FILTER_APP=""
LIMIT=""
WITH_GUI=true
ARTIFACT_DIR_OVERRIDE=""

INVENTORY_FILE=""
APPS_DIR=""
GUI_RESULTS_TSV=""
GUI_PLAN_TSV=""
RESULTS_CSV=""
SUMMARY_MD=""
LOG_FILE=""
PREF_BACKUP=""
SELECTED_MATRIX=""

usage() {
  cat <<'EOF'
Usage: scripts/ax_titlebar_survey.sh [options]

Options:
  --family <family>
  --priority <P0|P1|P2|Skip>
  --app <exact app name>
  --ax-only
  --with-gui
  --limit <N>
  --matrix <path>
  --artifact-dir <path>
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --family)
      FILTER_FAMILY="${2:-}"
      shift 2
      ;;
    --priority)
      FILTER_PRIORITY="${2:-}"
      shift 2
      ;;
    --app)
      FILTER_APP="${2:-}"
      shift 2
      ;;
    --ax-only)
      WITH_GUI=false
      shift
      ;;
    --with-gui)
      WITH_GUI=true
      shift
      ;;
    --limit)
      LIMIT="${2:-}"
      shift 2
      ;;
    --matrix)
      MATRIX_PATH="${2:-}"
      shift 2
      ;;
    --artifact-dir)
      ARTIFACT_DIR_OVERRIDE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument '$1'" >&2
      usage >&2
      exit 1
      ;;
  esac
done

[[ -f "$MATRIX_PATH" ]] || {
  echo "error: matrix file not found at $MATRIX_PATH" >&2
  exit 1
}

require_tool python3
require_tool swift

if [[ "$WITH_GUI" == "true" ]]; then
  run_test_preflight true
else
  run_test_preflight false
fi

if [[ -n "$ARTIFACT_DIR_OVERRIDE" ]]; then
  TEST_ARTIFACT_DIR="$ARTIFACT_DIR_OVERRIDE"
  mkdir -p "$TEST_ARTIFACT_DIR"
else
  init_artifact_dir titlebar-survey >/dev/null
fi

APPS_DIR="$TEST_ARTIFACT_DIR/apps"
mkdir -p "$APPS_DIR"
mkdir -p "$TEST_ARTIFACT_DIR/gui"

INVENTORY_FILE="$TEST_ARTIFACT_DIR/installed_apps.tsv"
GUI_RESULTS_TSV="$TEST_ARTIFACT_DIR/gui_results.tsv"
GUI_PLAN_TSV="$TEST_ARTIFACT_DIR/gui_plan.tsv"
RESULTS_CSV="$TEST_ARTIFACT_DIR/survey_results.csv"
SUMMARY_MD="$TEST_ARTIFACT_DIR/survey_summary.md"
LOG_FILE="$TEST_ARTIFACT_DIR/macsimize.log"
PREF_BACKUP="$TEST_ARTIFACT_DIR/prefs.plist"
SELECTED_MATRIX="$TEST_ARTIFACT_DIR/selected_matrix.csv"

python3 - "$INVENTORY_FILE" <<'PY'
import csv
import os
import subprocess
import sys
from pathlib import Path

output = Path(sys.argv[1])
roots = [
    Path("/Applications"),
    Path("/System/Applications"),
    Path("/Applications/Utilities"),
    Path.home() / "Applications",
]

special_paths = [
    Path("/System/Library/CoreServices/Finder.app"),
]

rows = []
seen = set()

def bundle_id(path: Path) -> str:
    try:
        return subprocess.check_output(
            ["mdls", "-raw", "-name", "kMDItemCFBundleIdentifier", str(path)],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return ""

for root in roots:
    if not root.exists():
        continue
    for path in sorted(root.glob("*.app")):
        key = path.name
        if key in seen:
            continue
        seen.add(key)
        rows.append((path.stem, bundle_id(path), str(path)))

for path in special_paths:
    if path.exists() and path.name not in seen:
        rows.append((path.stem, bundle_id(path), str(path)))

with output.open("w", newline="", encoding="utf-8") as handle:
    writer = csv.writer(handle, delimiter="\t")
    writer.writerow(["app_name", "bundle_id", "path"])
    writer.writerows(rows)
PY

matrix_rows() {
  python3 - "$MATRIX_PATH" <<'PY'
import csv
import sys

with open(sys.argv[1], newline="", encoding="utf-8") as handle:
    for row in csv.DictReader(handle):
        print(
            "\t".join(
                row[column]
                for column in [
                    "app_name",
                    "bundle_id",
                    "family",
                    "priority",
                    "prep_mode",
                    "window_mode",
                    "sample_profile",
                    "gui_validation",
                    "notes",
                ]
            )
        )
PY
}

find_bundle_path() {
  local app_name="$1"
  local bundle_id="$2"
  python3 - "$INVENTORY_FILE" "$app_name" "$bundle_id" <<'PY'
import csv
import sys

inventory, app_name, bundle_id = sys.argv[1:4]
match = ""
with open(inventory, newline="", encoding="utf-8") as handle:
    for row in csv.DictReader(handle, delimiter="\t"):
        if bundle_id and row["bundle_id"] == bundle_id:
            match = row["path"]
            break
        if row["app_name"] == app_name:
            match = row["path"]
            break
print(match)
PY
}

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-'
}

backup_preferences() {
  local output="$1"
  defaults export "$BUNDLE_ID" - >"$output" 2>/dev/null || true
}

restore_preferences() {
  local backup_file="$1"
  if [[ -s "$backup_file" ]]; then
    defaults import "$BUNDLE_ID" "$backup_file" >/dev/null 2>&1 || true
  else
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  fi
}

write_missing_probe_json() {
  local output="$1"
  local app_name="$2"
  local bundle_id="$3"
  local family="$4"
  local priority="$5"
  local sample_profile="$6"
  local status="$7"
  local notes="$8"
  python3 - "$output" "$app_name" "$bundle_id" "$family" "$priority" "$sample_profile" "$status" "$notes" <<'PY'
import json
import sys
from pathlib import Path

output, app_name, bundle_id, family, priority, sample_profile, status, notes = sys.argv[1:9]
payload = {
    "appName": app_name,
    "bundleID": bundle_id,
    "family": family,
    "priority": priority,
    "sampleProfile": sample_profile,
    "status": status,
    "windowFrame": "",
    "samples": [],
    "notes": notes,
}
Path(output).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

set_known_bounds_if_possible() {
  local app_name="$1"
  case "$app_name" in
    "Finder")
      osascript -e 'tell application "Finder" to set bounds of front window to {120, 120, 1040, 760}' >/dev/null 2>&1 || true
      ;;
    "Safari")
      osascript -e 'tell application "Safari" to set bounds of front window to {120, 120, 1040, 760}' >/dev/null 2>&1 || true
      ;;
    "Brave Browser")
      osascript -e 'tell application "Brave Browser" to set bounds of front window to {120, 120, 1040, 760}' >/dev/null 2>&1 || true
      ;;
    "Google Chrome")
      osascript -e 'tell application "Google Chrome" to set bounds of front window to {120, 120, 1040, 760}' >/dev/null 2>&1 || true
      ;;
    "TextEdit")
      osascript -e 'tell application "TextEdit" to set bounds of front window to {120, 120, 1040, 760}' >/dev/null 2>&1 || true
      ;;
    "Terminal")
      osascript -e 'tell application "Terminal" to set bounds of front window to {120, 120, 1040, 760}' >/dev/null 2>&1 || true
      ;;
  esac
}

prepare_app() {
  local app_name="$1"
  local prep_mode="$2"

  case "$prep_mode" in
    finder_home)
      osascript <<APPLESCRIPT >/dev/null 2>&1
tell application "Finder"
  activate
  if (count of windows) = 0 then make new Finder window
  set target of front window to home
  set bounds of front window to {120, 120, 1040, 760}
end tell
APPLESCRIPT
      ;;
    new_browser_window)
      case "$app_name" in
        "Safari")
          osascript <<APPLESCRIPT >/dev/null 2>&1
tell application "Safari"
  activate
  if (count of windows) = 0 then make new document
  set bounds of front window to {120, 120, 1040, 760}
end tell
APPLESCRIPT
          ;;
        "Brave Browser")
          osascript <<APPLESCRIPT >/dev/null 2>&1
tell application "Brave Browser"
  activate
  if (count of windows) = 0 then make new window
  set bounds of front window to {120, 120, 1040, 760}
end tell
APPLESCRIPT
          ;;
        "Google Chrome")
          osascript <<APPLESCRIPT >/dev/null 2>&1
tell application "Google Chrome"
  activate
  if (count of windows) = 0 then make new window
  set bounds of front window to {120, 120, 1040, 760}
end tell
APPLESCRIPT
          ;;
        *)
          open -a "$app_name" >/dev/null 2>&1 || true
          ;;
      esac
      ;;
    new_text_document)
      osascript <<APPLESCRIPT >/dev/null 2>&1
tell application "TextEdit"
  activate
  if (count of windows) = 0 then make new document
  set bounds of front window to {120, 120, 1040, 760}
end tell
APPLESCRIPT
      ;;
    activate_existing_window)
      case "$app_name" in
        "Terminal")
          osascript <<APPLESCRIPT >/dev/null 2>&1
tell application "Terminal"
  activate
  if (count of windows) = 0 then do script ""
  set bounds of front window to {120, 120, 1040, 760}
end tell
APPLESCRIPT
          ;;
        *)
          open -a "$app_name" >/dev/null 2>&1 || true
          ;;
      esac
      ;;
    open_app_only|manual_only)
      open -a "$app_name" >/dev/null 2>&1 || true
      ;;
    *)
      echo "error: unsupported prep_mode '$prep_mode' for '$app_name'" >&2
      return 1
      ;;
  esac

  sleep 1.0
  set_known_bounds_if_possible "$app_name"
  sleep 0.8
}

front_window_bounds_for_bundle() {
  local bundle_id="$1"
  swift - "$bundle_id" <<'SWIFT'
import AppKit
import ApplicationServices
import Foundation

let bundleID = CommandLine.arguments[1]
guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
    print("missing_app")
    exit(0)
}
let appElement = AXUIElementCreateApplication(app.processIdentifier)
func elementAttribute(_ attribute: String, on element: AXUIElement) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let value,
          CFGetTypeID(value) == AXUIElementGetTypeID() else {
        return nil
    }
    return unsafeDowncast(value, to: AXUIElement.self)
}
func pointAttribute(_ attribute: String, on element: AXUIElement) -> CGPoint? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let value,
          CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgPoint else { return nil }
    var point = CGPoint.zero
    return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
}
func sizeAttribute(_ attribute: String, on element: AXUIElement) -> CGSize? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let value,
          CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgSize else { return nil }
    var size = CGSize.zero
    return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
}
guard let window = elementAttribute(kAXFocusedWindowAttribute as String, on: appElement)
    ?? elementAttribute(kAXMainWindowAttribute as String, on: appElement),
      let point = pointAttribute(kAXPositionAttribute as String, on: window),
      let size = sizeAttribute(kAXSizeAttribute as String, on: window) else {
    print("missing_window")
    exit(0)
}
let frame = CGRect(origin: point, size: size)
print("\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.maxX)),\(Int(frame.maxY))")
SWIFT
}

record_gui_result() {
  local app_name="$1"
  local bundle_id="$2"
  local sample_label="$3"
  local screen_x="$4"
  local screen_y="$5"
  local expected_outcome="$6"
  expected_outcome="${expected_outcome//$'\r'/}"

  local before_bounds after_bounds before_lines captured actual_outcome pass_fail
  before_bounds="$(front_window_bounds_for_bundle "$bundle_id")"
  before_lines=$(wc -l < "$LOG_FILE" | tr -d ' ')
  "$CLICLICK_BIN" dc:"$screen_x","$screen_y" >/dev/null 2>&1 || true
  sleep 1.0
  after_bounds="$(front_window_bounds_for_bundle "$bundle_id")"
  captured="false"
  if tail -n +$((before_lines + 1)) "$LOG_FILE" | grep -Fq "Captured titlebar double-click"; then
    captured="true"
  fi

  if [[ "$before_bounds" != "$after_bounds" && "$captured" == "true" ]]; then
    actual_outcome="maximized_via_macsimize"
  elif [[ "$before_bounds" != "$after_bounds" ]]; then
    actual_outcome="window_changed_without_macsimize_capture"
  elif [[ "$captured" == "true" ]]; then
    actual_outcome="captured_without_frame_change"
  else
    actual_outcome="unchanged"
  fi

  pass_fail="FAIL"
  case "$expected_outcome" in
    blank_region_should_maximize|title_or_passive_region_should_maximize|blank_tabstrip_should_maximize)
      if [[ "$before_bounds" != "$after_bounds" && "$captured" == "true" ]]; then
        pass_fail="PASS"
      fi
      ;;
    control_should_not_maximize|tab_should_not_maximize)
      if [[ "$before_bounds" == "$after_bounds" && "$captured" == "false" ]]; then
        pass_fail="PASS"
      fi
      ;;
  esac

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$app_name" \
    "$bundle_id" \
    "$sample_label" \
    "$screen_x" \
    "$screen_y" \
    "$before_bounds" \
    "$after_bounds" \
    "$captured" \
    "$expected_outcome" \
    "$actual_outcome" \
    "$pass_fail" \
    >> "$GUI_RESULTS_TSV"
}

printf 'app_name\tbundle_id\tsample_label\tscreen_x\tscreen_y\tbefore_bounds\tafter_bounds\tmacsimize_capture_logged\texpected_outcome\tactual_outcome\tpass_fail\n' >"$GUI_RESULTS_TSV"
printf 'app_name,bundle_id,family,priority,prep_mode,window_mode,sample_profile,gui_validation,notes\n' >"$SELECTED_MATRIX"

if [[ "$WITH_GUI" == "true" ]]; then
  backup_preferences "$PREF_BACKUP"
  defaults write "$BUNDLE_ID" selectedAction -string maximize
  defaults write "$BUNDLE_ID" showSettingsOnStartup -bool false
fi

cleanup() {
  if [[ "$WITH_GUI" == "true" ]]; then
    restore_preferences "$PREF_BACKUP"
    stop_macsimize || true
  fi
}
trap cleanup EXIT

processed=0
while IFS=$'\t' read -r app_name bundle_id family priority prep_mode window_mode sample_profile gui_validation notes; do
  [[ -n "$app_name" ]] || continue
  if [[ -n "$FILTER_FAMILY" && "$family" != "$FILTER_FAMILY" ]]; then
    continue
  fi
  if [[ -n "$FILTER_PRIORITY" && "$priority" != "$FILTER_PRIORITY" ]]; then
    continue
  fi
  if [[ -n "$FILTER_APP" && "$app_name" != "$FILTER_APP" ]]; then
    continue
  fi
  if [[ -n "$LIMIT" && "$processed" -ge "$LIMIT" ]]; then
    break
  fi

  processed=$((processed + 1))
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$app_name" \
    "$bundle_id" \
    "$family" \
    "$priority" \
    "$prep_mode" \
    "$window_mode" \
    "$sample_profile" \
    "$gui_validation" \
    "$notes" \
    >>"$SELECTED_MATRIX"
  app_slug="$(slugify "$app_name")"
  output_json="$APPS_DIR/$app_slug.json"
  bundle_path="$(find_bundle_path "$app_name" "$bundle_id")"

  if [[ -z "$bundle_path" ]]; then
    write_missing_probe_json "$output_json" "$app_name" "$bundle_id" "$family" "$priority" "$sample_profile" "missing_bundle" "app bundle not found in installed inventory"
    continue
  fi

  if ! prepare_app "$app_name" "$prep_mode"; then
    write_missing_probe_json "$output_json" "$app_name" "$bundle_id" "$family" "$priority" "$sample_profile" "prep_failed" "prep mode failed"
    continue
  fi

  swift "$SCRIPT_DIR/titlebar_ax_probe.swift" \
    --app-name "$app_name" \
    --bundle-id "$bundle_id" \
    --family "$family" \
    --priority "$priority" \
    --sample-profile "$sample_profile" \
    >"$output_json"
done < <(matrix_rows)

python3 "$SCRIPT_DIR/titlebar_survey_report.py" \
  --matrix "$SELECTED_MATRIX" \
  --apps-dir "$APPS_DIR" \
  --results-csv "$RESULTS_CSV" \
  --summary-md "$SUMMARY_MD" \
  --gui-plan "$GUI_PLAN_TSV" \
  --gui-results "$GUI_RESULTS_TSV" \
  --build-identity "${APP_BIN:-unknown}" \
  $([[ "$WITH_GUI" == "true" ]] && printf '%s' '--with-gui')

if [[ "$WITH_GUI" == "true" && $(wc -l < "$GUI_PLAN_TSV") -gt 1 ]]; then
  start_macsimize "$LOG_FILE"

  tail -n +2 "$GUI_PLAN_TSV" | while IFS=$'\t' read -r app_name bundle_id family priority prep_mode sample_label screen_x screen_y expected_outcome; do
    [[ -n "$app_name" ]] || continue
    expected_outcome="${expected_outcome//$'\r'/}"
    prepare_app "$app_name" "$prep_mode" || true
    record_gui_result "$app_name" "$bundle_id" "$sample_label" "$screen_x" "$screen_y" "$expected_outcome"
  done

  python3 "$SCRIPT_DIR/titlebar_survey_report.py" \
    --matrix "$SELECTED_MATRIX" \
    --apps-dir "$APPS_DIR" \
    --results-csv "$RESULTS_CSV" \
    --summary-md "$SUMMARY_MD" \
    --gui-plan "$GUI_PLAN_TSV" \
    --gui-results "$GUI_RESULTS_TSV" \
    --build-identity "${APP_BIN:-unknown}" \
    --with-gui
fi

printf 'survey_artifact_dir=%s\n' "$TEST_ARTIFACT_DIR"
printf 'survey_results=%s\n' "$RESULTS_CSV"
printf 'survey_summary=%s\n' "$SUMMARY_MD"
