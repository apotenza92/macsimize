# Macsimize Manual Test Plan

## 1. Launch and menu bar basics

- Launch `Macsimize.app` directly.
- Confirm the app appears only in the menu bar and does not keep a Dock icon.
- Confirm the Settings window opens on first launch or Finder launch.
- Reopen Settings from the menu bar.
- Confirm the menu contains:
  - `Maximize All` or `Maximise All`, depending on system English
  - `Settings…`
  - `Quit Macsimize`

## 2. Permissions and interception readiness

- Confirm the Permissions section reflects current Accessibility and Input Monitoring state.
- Use `Open Accessibility` and `Open Input Monitoring` to verify the correct System Settings panes open.
- Grant both permissions, click `Refresh`, and confirm the status moves to `Ready`.
- With diagnostics enabled, confirm the recent diagnostics list updates while interactions are exercised.

## 3. Green button maximize and restore

Use these apps:

- TextEdit
- Finder
- Safari

For each app and at least one window on each connected display:

1. Set Macsimize to `Maximize` / `Maximise`.
2. Record the original bounds.
3. Click the green button once.
4. Confirm the window fills the visible frame of the chosen display.
5. Click the green button again.
6. Confirm the original bounds are restored or closely approximated.

## 4. Titlebar double-click override

For TextEdit, Finder, and Safari:

1. Keep Macsimize in `Maximize` / `Maximise` mode.
2. Double-click the titlebar or unified toolbar.
3. Confirm Macsimize toggles its maximize/restore behavior instead of native macOS zoom/fill.
4. Double-click again.
5. Confirm the prior frame restores.

Expected:

- Native titlebar double-click zoom/fill should not occur in maximize mode.
- Diagnostics should mention titlebar double-click capture.

## 5. Drag-restore from managed maximize

For TextEdit, Finder, and Safari:

1. Maximize the window with Macsimize.
2. Click and drag from the titlebar or toolbar.
3. Confirm the window restores to its prior size as the drag begins.
4. Confirm the drag continues naturally with the restored window under the pointer.
5. Release and maximize again.
6. Resize or move the window manually, then drag again to confirm stale maximize state does not restore incorrectly.

Expected:

- Drag-restore should only trigger for a Macsimize-managed maximized window.
- Diagnostics should distinguish drag-restore triggered vs skipped.

## 6. Full Screen pass-through

For TextEdit, Finder, and Safari:

1. Set Macsimize to `Full Screen`.
2. Click the green button.
3. Confirm native macOS full-screen behavior occurs.
4. Double-click the titlebar.
5. Confirm native macOS titlebar behavior remains unchanged in this mode.

## 7. Maximize All in the current Space

Prepare:

- Desktop 1 as a control Space
- Desktop 2 with at least one eligible app window
- Desktop 3 with the same app and another eligible window

Validate:

1. Switch to Desktop 2.
2. Trigger `Maximize All` / `Maximise All` from the menu bar.
3. Confirm eligible Desktop 2 windows maximize.
4. Switch to Desktop 3.
5. Confirm Desktop 3 windows remain unchanged.
6. Trigger `Maximize All` / `Maximise All` from Desktop 3.
7. Confirm only Desktop 3 windows now maximize.

Also verify:

- Macsimize skips its own windows.
- Sheets, panels, minimized windows, and non-resizable windows are not processed.
- Diagnostics mention skipped reasons for ineligible windows.

## 8. Multi-display behavior

- Repeat maximize, titlebar double-click, and drag-restore on windows positioned:
  - fully on the primary display
  - fully on a secondary display
  - straddling two displays
- Confirm maximize selects the expected target display.
- Confirm drag-restore keeps the restored window under the pointer.

## 9. Localization

Repeat the core menu and settings checks with system English set to:

- `en`
- `en-GB`
- `en-AU`

Confirm:

- `Maximize` vs `Maximise` is used consistently in the menu, settings, and help text.
- `Behavior` vs `Behaviour` follows the system English variant.
- Permission, update, and diagnostics-facing status copy remains coherent across variants.

## 10. Diagnostics

- Enable diagnostics.
- Exercise green-button maximize/restore, titlebar double-click, drag-restore, and `Maximize All`.
- Confirm recent diagnostics/logs clearly distinguish:
  - deterministic maximize
  - restore toggle
  - titlebar double-click capture
  - drag-restore triggered
  - drag-restore skipped
  - batch maximize
  - current-Space skip or filter reasons
