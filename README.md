# Macsimize

<img src="Macsimize/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" alt="Macsimize icon" width="96" />

Macsimize is a lightweight macOS menu bar app that remaps a clean click on the green window button to either deterministic maximize behavior or the normal macOS full-screen action.

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

1. Download the latest zip from GitHub Releases.
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

## Releases

Releases follow the same tag-driven flow as Docktor:

1. Add a `## [vX.Y.Z]` or `## [vX.Y.Z-beta.N]` section to `CHANGELOG.md`.
2. Ensure `MARKETING_VERSION` in `Macsimize.xcodeproj` matches the core version.
3. Run `./scripts/release.sh <version>` from a clean `main` branch.
