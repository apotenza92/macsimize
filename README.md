# Macsimize

![Macsimize icon](Macsimize/Assets.xcassets/AppIcon.appiconset/icon_256x256.png)

Macsimize is a menu-bar-first macOS app for remapping a clean single-click on the green window button.

## App model

- Native menu bar app with a minimal Docktor-style status menu
- Dedicated native settings window for behavior, permissions, exclusions, and diagnostics
- Menu bar menu intentionally stays minimal: **Settings…** and **Quit**
- Global left-mouse event tap that only remaps clean clicks on the green window button

## Green-button modes

Macsimize now exposes two modes only:

- **Maximize**
  - Uses Macsimize’s deterministic Accessibility resize logic
  - Resizes the clicked window to the current display’s visible usable frame
  - Stores the previous frame so the next clean click restores it
- **Full Screen**
  - Passes the click through unchanged
  - Lets macOS handle the app’s normal full-screen behavior

## Behavior details

### Maximize

On a clean intercepted click, Macsimize:

1. Identifies the clicked green button and parent window through Accessibility.
2. Chooses the best display for the window.
3. Resizes the window to that display’s visible frame.
4. Restores the prior frame on the next clean click when the window is still near the maximized target.

### Full Screen

When **Full Screen** is selected, Macsimize does not consume the click. The app simply lets the original green-button action proceed normally.

## Permissions

Macsimize may need:

1. **Accessibility** — required for button hit-testing and window resize/restore.
2. **Input Monitoring** — often required for the global click tap.

Open from System Settings:

- `Privacy & Security > Accessibility`
- `Privacy & Security > Input Monitoring`

## Stable / Beta builds

Macsimize now follows the same side-by-side build pattern as Docktor:

- stable uses:
  - app name: `Macsimize`
  - bundle id: `com.example.Macsimize`
  - icon: `AppIcon`
- beta can be built side by side with:
  - app name: `Macsimize Beta`
  - bundle id: `com.example.Macsimize.beta`
  - icon: `AppIconBeta`

Example beta build:

```bash
xcodebuild \
  -project Macsimize.xcodeproj \
  -scheme Macsimize \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  PRODUCT_NAME='Macsimize Beta' \
  PRODUCT_BUNDLE_IDENTIFIER='com.example.Macsimize.beta' \
  ASSETCATALOG_COMPILER_APPICON_NAME='AppIconBeta' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Testing

Automated coverage includes settings migration, maximize geometry, restore behavior, and click interception.

Run unit tests with:

```bash
xcodebuild test -project Macsimize.xcodeproj -scheme Macsimize -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

### Included test coverage

- settings persistence and legacy action migration
- maximize target selection and restore toggling
- window frame bookkeeping
- window action engine behavior for maximize vs full screen
- click interception state machine
  - full screen passes through
  - maximize consumes clean clicks
  - drag exceeds threshold and replays original click
  - long press replays original click

### Shell automation

- `scripts/automated_settings_shell_checks.sh`
  - launches the app with `--settings`
  - verifies a settings window appears
  - verifies repeated settings handoff to the running instance
- `scripts/automated_green_button_checks.sh`
  - launches Macsimize in **Maximize** mode
  - launches a TextEdit fixture window
  - clicks the real green button with `cliclick`
  - verifies the first click meaningfully expands the window
  - verifies the second click restores near the original bounds
  - verifies maximize diagnostics are emitted
Requirements:

- `cliclick` installed for click automation
- Accessibility granted to the controlling terminal and to `Macsimize`
- Input Monitoring granted where needed for the event tap

## Manual verification

OS-level event taps and Accessibility behavior remain app- and machine-dependent. Use `Tests/ManualTestPlan.md` to verify:

- maximize expands to the usable visible frame
- second click restores
- full screen passes through to macOS
- excluded apps, non-resizable windows, drag, and hold behavior

## Known limitations

- Some apps expose non-standard title bars or custom green-button behavior, so hit-testing can still vary by app.
- Verification depends on short polling windows after AX resize operations, so timing remains app-dependent.
- Non-resizable windows are left alone.
- Hover-glyph replacement is still not fully implemented.
