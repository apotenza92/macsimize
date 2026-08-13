# Macsimize repository instructions

## Verification workflow

- `.github/workflows/ci.yml` is manually invoked with `workflow_dispatch`; routine pushes and pull requests do not start GitHub-hosted CI.
- `.github/workflows/release.yml` remains restricted to deliberate `v*` tag pushes.
- Local pre-tag validation owns XCTest. The tag workflow starts signed package builds after tag-contract validation instead of repeating the same native test matrix first.

## Release credential boundaries

- `release-signing` contains the Developer ID P12, its password, and the App Store Connect P8. Only native package jobs may use it.
- `sparkle-signing` is tag-restricted and contains only `SPARKLE_PRIVATE_ED_KEY`. Only updater verification and appcast-signing jobs may use it.
- `stable-release` and `beta-release` are secret-free publication controls used only by the final public-release job. Draft staging, updater verification, and publication-bundle preparation must not consume their approval gate.
- Appcasts remain checksum-sealed workflow artefacts for deliberate publication. Homebrew uses the common attested release bundle and a protected dispatch-only GitHub App credential. The source workflow dispatches publication without waiting and never writes the tap. The tap reports and retries publication independently.
- Keep `APPLE_NOTARYTOOL_KEY_ID`, `APPLE_NOTARYTOOL_ISSUER_ID`, signing identities, team IDs, and certificate fingerprints in GitHub variables, not secrets.
- Never expose release environments to pull-request jobs or workflows triggered by untrusted content.
- `homebrew-dispatch` is tag-restricted and contains only the Homebrew Dispatcher GitHub App private key. The App can dispatch Actions in `apotenza92/homebrew-tap` and has no Contents write permission.
- Release tags must resolve to commits reachable from the repository's `main` default branch.
