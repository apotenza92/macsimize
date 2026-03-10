# Macsimize

<img src="Macsimize/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" alt="Macsimize icon" width="96" />

<a href="https://apotenza92.github.io/macsimize/">
  <img src="https://img.shields.io/badge/Download-Macsimize-49c96a?style=for-the-badge&logo=apple&logoColor=white" alt="Download Macsimize" height="40">
</a>
<br><br>

Macsimize turns the green window button into Maximize instead of Full Screen.

It also overrides title-bar double-click to use the same maximize behavior.

Click the Macsimize app icon in the menu bar to use `Maximize All` and `Restore All` for the windows in your current space.

Enjoying Macsimize?

[![Buy me a coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=000000)](https://buymeacoffee.com/apotenza)

## Install

### Homebrew

```bash
brew tap apotenza92/tap
brew install --cask apotenza92/tap/macsimize
```

Beta can be installed side by side with stable:

```bash
brew tap apotenza92/tap
brew install --cask apotenza92/tap/macsimize@beta
```

### Manual install

1. Download the latest zip from the [download page](https://apotenza92.github.io/macsimize/) or [GitHub Releases](https://github.com/apotenza92/macsimize/releases).
2. Move `Macsimize.app` (or `Macsimize Beta.app`) to `/Applications`.
3. Launch once and grant permissions.

## Required macOS Permissions

- Accessibility
- Input Monitoring

System Settings paths:

- `Privacy & Security > Accessibility`
- `Privacy & Security > Input Monitoring`

## Build

```bash
xcodebuild -project Macsimize.xcodeproj -scheme Macsimize -configuration Debug build
```

## Test

```bash
xcodebuild test -project Macsimize.xcodeproj -scheme Macsimize -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```
