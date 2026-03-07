# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

- No unreleased changes yet.

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
