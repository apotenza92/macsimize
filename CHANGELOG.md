# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

- No unreleased changes yet.

## [v0.2.11]

- Moved the readiness icon and explanatory text into the Permissions section so setup status now appears alongside the permission controls instead of as a separate panel at the top of Settings.

## [v0.2.10]

- Fixed a failure path where an intercepted Maximize click could fall back to native macOS full screen instead of staying contained.
- Changed intercepted maximize failures and non-resizable window cases to swallow the click rather than replaying the original green-button press.
- Added a first-run status panel and clearer readiness messaging so Macsimize now explains when permissions or the event tap are still preventing interception.
- Automatically opens Settings whenever required permissions are missing so new installs do not appear active before green-button interception is actually ready.

## [v0.2.10-beta.1]

- Made the app resolve its display name from bundle metadata so stable and beta builds label themselves consistently at runtime.
- Updated the Settings window title, menu bar tooltip, quit menu item, and related visible strings to show `Macsimize Beta` for beta builds and `Macsimize` for stable builds.
- Added coverage for runtime app-name resolution and parameterized the Accessibility usage description with `$(PRODUCT_NAME)`.

## [v0.2.9]

- Fixed a maximize/restore CPU spike regression by removing unbounded AX fallback traversal from the event-tap click path and replacing it with bounded, fail-open lookup behavior.
- Added strict traffic-light hit-zone gating for focused/main window button lookup so non-titlebar clicks avoid expensive accessibility resolution.
- Added a short post-action interception suppression window to prevent rapid re-entry during maximize/restore animation transitions.
- Expanded interception tests with titlebar hot-zone coverage checks and validated behavior with repeated automated maximize/restore stress runs.

## [v0.2.8]

- Hardened Sparkle integration for menu bar safety by making manual update checks non-blocking, adding updater state diagnostics, and gating launcher-service-dependent startup paths.
- Reduced menu bar interaction stalls by bypassing event-tap accessibility resolution for menu bar region clicks before expensive AX traversal.
- Added release and CI Sparkle bundle validation plus release workflow resilience for transient Apple timestamp service outages during signing/export.

## [v0.2.7]

- Reduced false-positive AX permission churn by preferring frontmost-app hit testing and only using system-wide AX hit testing as a fallback path.
- Hardened singleton startup so stale Macsimize instances are terminated (with escalation) before a new menu-bar instance proceeds.
- Reduced CPU spikes from no-op state churn by deduplicating permission/event-tap state publishes and avoiding redundant secure-input polling on unchanged tap status updates.

## [v0.2.6]

- Fixed the Settings action toggle so switching between Maximize and Full Screen applies immediately in the running app instead of lagging one click behind.
- Updated the Settings UI buttons and live interception refresh path so the selected mode is written and activated on the same click.
- Hardened the green-button automation helper and verified the live toggle flow end to end against a real TextEdit window with native macOS screenshots.

## [v0.2.5]

- Rewrote the Settings action selector to use a native radio-group control so Maximize and Full Screen persist and reflect the active choice reliably.
- Changed legacy `systemDefault` migration so upgraded installs now land on Maximize instead of silently defaulting to Full Screen.
- Strengthened the end-to-end regression harness to verify a fresh default of Maximize, Settings toggling in both directions, and real green-button behavior for both Maximize and Full Screen.

## [v0.2.4]

- Fixed the Settings action picker so Maximize and Full Screen persist and apply the selected mode immediately without crashing or lagging one click behind.
- Cleaned up startup permission handling so signed development and release builds no longer emit false Accessibility/Input Monitoring denial churn before the event tap starts.
- Verified the maximize and full-screen modes end to end against a real green-button click on TextEdit, in addition to the automated test suite.

## [v0.2.3]

- Fixed the Settings action-mode control so switching between Maximize and Full Screen applies the selected behavior immediately instead of behaving one click behind.

## [v0.2.2]

- Added startup permission prompting for Accessibility and Input Monitoring so first-run and reopened launches behave like a standard macOS utility app.
- Added native Sparkle update support with in-app update checks and configurable update frequency in Settings.
- Added signed Sparkle appcast generation for stable and beta channels and wired it into the release workflow.
- Added dedicated Macsimize Sparkle signing key support and embedded per-channel Sparkle feed URLs in release builds.

## [v0.2.1]

- Added menu-bar-first green-button interception with maximize and full-screen modes.
- Added stable and beta side-by-side app variants for release builds.
- Added automated settings shell checks and green-button regression checks.
- Fixed release automation issues that blocked signed archive builds.
- Simplified the settings window layout and fixed first-launch and reopen behavior.
- Removed the ignored-apps and diagnostics controls from the settings UI.
