# Narrow maximise migration status for Macsimize

Last updated: 2026-04-13
Status: maximise path cleaned up; titlebar/restore follow-up remains

## Scope

Macsimize remains intentionally narrow. The supported behaviour set is still:

1. green button click → Macsimize maximise
2. titlebar double-click → Macsimize maximise
3. drag away from a Macsimize-managed maximised window → restore previous size

Rectangle is being used only as a reference for:
- frame application order
- restore/history structure
- titlebar double-click flow
- drag-away restore geometry

It is not a blueprint for snapping, tiling, shortcuts, or general window management.

## What is now complete

### Green-button interception reliability

The intermittent Brave miss was traced to resolving the click against the frontmost app before activation had caught up. Macsimize now:
- performs a system-wide AX hit-test first
- resolves the clicked element's owning app/window from that hit result
- only falls back to frontmost-window lookup when necessary

That keeps interception tied to the actual clicked window, including freshly activated Brave windows.

### Maximise frame application

The old repair-heavy maximise path has been removed.

The current maximise path now:
- computes the visible-frame target for the chosen screen
- temporarily disables `AXEnhancedUserInterface` when needed
- applies maximise using a direct accessibility frame sequence
- writes position first, then final size by default
- polls only to observe the settled frame, not to drive repeated repair loops

The position-first ordering is the part that removed Brave's visible intermediate grow on same-screen maximise.

### Per-window transaction tracking

Macsimize still keeps its own interception/runtime pieces:
- green-button consume/replay logic
- exact window identity via `WindowInterceptionKey`
- per-window transaction suppression while a managed maximise is settling
- observer-backed mutation completion in `EventTapService`

None of the old PID-wide timeout suppression behaviour has been reintroduced.

### Automated Brave regression coverage

The Brave harness remains part of the acceptance gate.

Important guardrails stay in place:
- each run creates a brand new Brave test window
- the exact Brave window id is tracked
- only that test window is closed afterwards
- existing Brave windows are left alone

## Current evidence

Latest successful validation after cleanup:

- `xcodebuild test -scheme Macsimize -destination 'platform=macOS'`
  - passed
- `BRAVE_RUN_COUNT=10 ./scripts/automated_brave_instant_maximize_checks.sh`
  - passed
  - every run showed only two distinct frames:
    - the starting frame
    - the final maximised frame

This means the maximise path is now in the desired state for Brave:
- interception succeeds reliably enough for repeated runs
- maximise lands directly at the visible-frame target without a visible intermediate frame

## Cleanup completed in this pass

- removed the temporary experimental preference
- removed the old observer/repair-loop maximise branch
- removed dead maximise test coverage for deleted helpers
- simplified `MaximizeStrategy` to a single direct frame-apply path
- kept the transaction expectation plumbing required by `EventTapService`
- updated this document so it reflects the current runtime rather than the old experiment phase

## Remaining follow-up work

The remaining work is now narrower and cleaner:

### 1. Consolidate maximise/titlebar/restore into one shared action pipeline

Still worth doing:
- keep green-button interception as Macsimize-specific
- keep custom-chrome titlebar detection as Macsimize-specific
- route green button and titlebar double-click into the same narrow maximise/restore engine

### 2. Tighten restore/history structure

Still worth doing:
- separate last restore rect from last Macsimize-managed action more explicitly
- keep current exact window identity model
- preserve stacked-display correctness from `ScreenHelpers`

### 3. Finish the narrowed titlebar double-click and drag-away restore work

Still worth doing:
- keep the current custom-chrome hit-testing improvements
- apply the shared maximise engine to titlebar double-clicks
- preserve cursor-inside-window behaviour on drag-away restore
- keep automated coverage around those flows

## Non-goals

Still explicitly out of scope:
- snapping
- tiling
- halves, thirds, corners, fourths, eighths
- display movement
- keyboard shortcut infrastructure
- menu-driven multi-action window management
- turning Macsimize into a general window manager

## Practical verdict

The useful Rectangle lessons for Macsimize were narrow:
- simple visible-frame maximise targeting
- direct AX frame application structure
- restore/history separation ideas
- titlebar/restore flow references

The Macsimize-specific pieces remain essential:
- green-button interception
- custom-chrome titlebar detection
- per-window transaction suppression
- Brave instant-maximise regression testing
