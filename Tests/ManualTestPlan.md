# Macsimize Manual Test Plan

## 1. Launch and settings window

- Launch `Macsimize.app` directly.
- Confirm the app appears in the menu bar with no Dock icon.
- Confirm a dedicated **Macsimize Settings** window opens on first launch or Finder launch.
- Close and reopen settings from the menu bar.
- Confirm the window frame persists across relaunches.

## 2. Permissions

- In the settings window, confirm the **Permissions** section reflects current state.
- Click **Open Accessibility** and confirm System Settings opens correctly.
- Click **Open Input Monitoring** and confirm System Settings opens correctly.
- After granting permissions, click **Refresh**.
- Confirm status changes to **Interception Running** once the event tap starts.

## 3. Menu bar and settings behavior

- Open the menu bar item.
- Confirm it shows only:
  - **Settings…**
  - **Quit Macsimize**
- Choose **Settings…** and confirm the settings window becomes frontmost.
- Relaunch Macsimize from Finder and confirm the existing instance brings Settings forward.

## 4. Maximize behavior

Use these apps first:

- TextEdit
- Finder windows
- Safari

Test on the primary display and at least one secondary display when available.

For each app/window combination:

1. Record the original bounds.
2. Set Macsimize to **Maximize**.
3. Single-click the green button.
4. Record the resulting bounds.
5. Click the green button again.
6. Confirm the original bounds are restored or very closely approximated.

Expected:

- The first click should expand the window to the display’s visible usable frame.
- The second click should restore the prior bounds.
- Diagnostics should clearly mention deterministic maximize behavior.

## 5. Full Screen pass-through behavior

For TextEdit, Finder, and Safari:

1. Set Macsimize to **Full Screen**.
2. Single-click the green button.
3. Confirm standard macOS full-screen behavior occurs.
4. Exit full screen and repeat once more.

Expected:

- Macsimize should not remap the click in this mode.
- Native app/macOS full-screen animation and behavior should remain intact.

## 6. Click-threshold behavior

- In **Maximize** mode, press and hold the green button longer than a normal click.
- Confirm Macsimize replays the original click instead of maximizing.
- In **Maximize** mode, click the green button and drag before release.
- Confirm Macsimize flushes the buffered native events and does not perform deterministic maximize.

## 7. Non-resizable and excluded-app cases

- Find or create a non-resizable window.
- In **Maximize** mode, click the green button.
- Confirm Macsimize does not resize it.
- Add the frontmost app from the settings window to exclusions.
- Click the green button in that app.
- Confirm Macsimize no longer remaps the click.
- Remove the bundle ID manually and confirm remapping resumes.

## 8. Diagnostics

- Enable diagnostics.
- Trigger several green-button clicks in both modes.
- Confirm recent log lines appear in the settings window.
- Use **Snapshot Frontmost Window** and confirm AX details are logged.
- Confirm logs make it clear whether the action used:
  - deterministic maximize
  - restore toggle
  - pass-through/full screen
  - replay because click thresholds were exceeded

## 9. Multi-display sampling

- Place windows mostly on the primary display, mostly on a secondary display, and straddling both.
- In **Maximize** mode, confirm the chosen target is the visible frame of the best-matching display.
- Confirm restore returns to the original display/frame.
