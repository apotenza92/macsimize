# Titlebar AX Survey

## Purpose

This survey exists to measure how Macsimize's titlebar interception assumptions line up with real macOS apps. The focus is broad coverage first: identify the dominant AX structures for popular installed apps, flag outliers, and only then decide whether the runtime needs new heuristics.

This is an advisory survey. It is not a required release gate by default.

## Inputs

The survey combines:

- a checked-in matrix of target apps in `Tests/titlebar_app_matrix.csv`
- live app discovery from standard app locations
- AX hit-testing of the top chrome of each app window
- optional GUI double-click validation for selected high-risk or representative apps

## Family Model

Apps are grouped into one of these families:

- `apple_native_standard`
- `apple_native_unified_toolbar`
- `chromium_browser`
- `firefox_browser`
- `electron_app`
- `editor_ide_native`
- `editor_ide_web_shell`
- `office_productivity`
- `media_creation`
- `terminal_emulator`
- `communication_collaboration`
- `utility_menu_or_desktop`
- `unknown`

The matrix is the source of truth. If an app is not present there, the survey can still classify it heuristically, but checked-in rows win.

## Priority Model

- `P0`: most important installed and mainstream apps, or families already known to have unusual top chrome
- `P1`: common desktop apps worth probing after P0
- `P2`: lower-priority or redundant representatives
- `Skip`: apps deliberately excluded from the survey

## Matrix Columns

`Tests/titlebar_app_matrix.csv` uses these columns:

- `app_name`
- `bundle_id`
- `family`
- `priority`
- `prep_mode`
- `window_mode`
- `sample_profile`
- `gui_validation`
- `notes`

### `prep_mode`

- `finder_home`
- `new_browser_window`
- `new_text_document`
- `activate_existing_window`
- `open_app_only`
- `manual_only`

### `window_mode`

- `standard_window`
- `browser_window`
- `document_window`
- `editor_window`
- `custom_window`
- `utility_window`

### `sample_profile`

- `standard_titlebar`
- `unified_toolbar`
- `browser_tabstrip`
- `editor_custom_toolbar`
- `unknown_top_chrome`

### `gui_validation`

- `always`: always attempt live validation if GUI mode is enabled
- `auto`: validate only when the survey rules select the app
- `never`: do not attempt GUI validation

## Structure Classes

Each sampled point is classified as one of:

- `native_window`
- `toolbar_control`
- `toolbar_passive`
- `static_title_region`
- `chromium_tab`
- `chromium_tabstrip_blank`
- `unknown_container`
- `unsupported`

## Risk Model

### Low

- direct `AXWindow`
- `AXStaticText -> AXWindow`
- passive `AXToolbar` / `AXGroup` regions without controls
- current known Chromium blank-tabstrip pattern

### Medium

- unusual passive containers such as `AXSplitGroup`
- deep passive group chains that still terminate at the window
- mixed passive regions in dense toolbars

### High

- `AXTabGroup` structures that are not the known blank-tabstrip spacer
- duplicated leaf-group patterns that look tab-like
- unknown top-level roles in the titlebar band
- apps whose top-chrome samples all resolve to controls or unknown containers
- user-facing apps that cannot expose a usable front window during prep

## GUI Validation Policy

GUI validation is selective. It should run when:

- the matrix says `gui_validation=always`
- any sampled point for the app is `high` risk
- the app is the first representative of a family
- a `P0` app exposes a structure class not previously seen in that family

Common GUI expectations:

- passive titlebar region should maximize
- toolbar controls should not maximize
- Chromium tab should not maximize
- Chromium blank tabstrip should maximize

## Artifacts

By default the survey writes artifacts under:

- `/tmp/macsimize-artifacts/titlebar-survey-<timestamp>/`

Expected outputs:

- `survey_results.csv`
- `survey_summary.md`
- per-app raw AX probe JSON under `apps/`
- GUI validation records under `gui/`

## Running

Examples:

```bash
scripts/ax_titlebar_survey.sh
scripts/ax_titlebar_survey.sh --ax-only
scripts/ax_titlebar_survey.sh --family chromium_browser --with-gui
scripts/ax_titlebar_survey.sh --app "Brave Browser" --with-gui
```

## Reading The Results

Each app should end in one of:

- `covered`
- `covered_with_risk`
- `needs_follow_up`
- `inconclusive`

Interpretation:

- `covered`: observed structures match known safe heuristics
- `covered_with_risk`: mostly covered, but medium-risk structures deserve caution
- `needs_follow_up`: unknown or high-risk structures likely need more exploration or new heuristics
- `inconclusive`: the survey could not obtain a useful front window or AX data

## Adding New Apps

1. Add a row to `Tests/titlebar_app_matrix.csv`.
2. Pick the closest `family`, `prep_mode`, and `sample_profile`.
3. Prefer `auto` GUI validation unless the app is a deliberate family reference.
4. Re-run the survey for the app first:

```bash
scripts/ax_titlebar_survey.sh --app "App Name" --ax-only
```

5. Promote to GUI validation if the AX structure looks unusual or high-risk.
