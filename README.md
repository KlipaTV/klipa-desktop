# Klipa Player for Desktop

Klipa Player is a lightweight, local-first IPTV player for
Windows and Linux. It is designed for people who bring their own M3U/M3U8 playlist or
Xtream-compatible login. It includes no channels, subscriptions, ads, accounts,
or telemetry.

The product has a separate history and runtime from the Klipa mobile app. The
desktop UI shares Klipa's visual language, while its navigation and interaction
model are desktop-native.

## Current status

Public source, pre-release candidate:

- Native Windows and Linux Flutter runners in one local Git repository
- Klipa desktop shell, bounded M3U import, search and single-player vertical slice
- Masked Xtream login with bounded, live-only account/category/stream requests
- Compact category filtering and background-isolate playlist parsing
- Compact live controls for play/pause, mute, app-session volume, fit mode and
  native full screen, with focus-scoped keyboard shortcuts and playback-only
  auto-hide
- Race-safe channel replacement behind a small playback port, with teardown-first
  switching, bounded readiness, retry, and generic user-facing native errors
- Strict HTTP(S), redirect, size, header, protocol and private-network controls
- Import-time disclosure that HLS/DASH sources may choose nested media hosts;
  the lightweight player trusts each user-added source for destinations while
  continuing to treat its metadata and media as untrusted input
- Versioned SQLite3MultipleCiphers schema, atomic snapshot writes, Windows
  DPAPI and Linux Secret Service key-sealing, reset primitives, and
  database/WAL/SHM leak tests
- Encrypted library save and startup restore on a background isolate; a failed
  save leaves the previous working snapshot active
- Stable multi-source identities, source/group filtering, rename, confirmed
  delete, and atomic refresh with `Ctrl+R`
- Encrypted per-channel favorites with responsive row toggles and a composable
  favorites-only filter; stable favorites survive source refresh
- Encrypted last source/group/channel state with stale-identity validation and
  an explicit one-click Resume action that never autoplays on startup
- Provider guide IDs, provider-direct bounded XMLTV retrieval, a plain/gzip
  parser, atomic encrypted now/next snapshots, Xtream import/refresh integration,
  an optional encrypted M3U guide address, and compact current-programme labels
  are implemented
- Runtime networking has no Klipa service dependency: install and startup make
  no Klipa request, and provider data is never routed through Klipa
- Confirmed reset and missing/corrupt-key recovery are wired; external
  distribution security and signing gates are implemented through
  SignPath code signing and the GitHub Actions release workflow
- Native Windows debug build, DPAPI, encrypted database and libmpv smoke tests pass
- Native release build and an authorized private MPEG-TS playback smoke pass
- Native Linux release bundle builds at about 29 MiB before packaging; local
  files use the same maintained picker on Windows and Linux
- A no-admin Windows installer (about 26 MiB), Windows portable archive, and
  Debian/Ubuntu package (about 9.7 MiB) build locally
- Real Windows and Linux install, clean-start, zero-TCP, and uninstall smoke
  tests pass; neither installer adds an updater, service, or scheduled task
- Release tooling generates a 123-component CycloneDX SBOM, exact native hashes
  and versions, license notices, and a high/critical vulnerability gate
- Deterministic release fuzzing covers M3U, XMLTV, and Xtream inputs; optional
  Windows Authenticode and Linux detached-signature paths keep keys external
- Public source at https://github.com/KlipaTV/klipa-desktop; signed Windows
  releases are published from tagged commits via the release workflow

The Windows toolchain uses Flutter 3.44.6 stable, Visual Studio Build Tools
2022, the Desktop development with C++ workload, and Windows SDK 10.0.26100.

Run `tool/build_windows.ps1` from PowerShell for the full native Windows
validation (analyze, build, test). It builds in a synchronized mirror under
`%USERPROFILE%\develop\klipa-player-windows-native`, which keeps builds
working when the checkout lives on a filesystem where Windows Flutter cannot
create its package symlinks (for example a WSL UNC path).

## Development

Prerequisites:

- Flutter 3.44.6 stable
- Dart 3.12+
- Windows 11 or Windows 10 22H2 x64
- Visual Studio with Desktop development with C++ for native builds
- On Linux: GTK 3 development files, libmpv, and libsecret

```powershell
flutter pub get
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter build windows --release
# Linux: flutter build linux --release
```

Automated tests use only synthetic fixtures or legally documented
interoperability streams. An authorized private provider may be used for a
manual local smoke test through the masked UI, but never include its URL,
username, password, token, or authorization headers in source, commands, logs,
issues, tests, or screenshots.

On Windows, library data is stored below the app-specific directory in
`%LOCALAPPDATA%`. The database is encrypted as a whole and its random key is
sealed to the current Windows user with DPAPI. There is no plaintext fallback.
Linux uses the same encrypted database and stores only its random key in the
desktop Secret Service keyring.

The application has no Klipa API, telemetry, update-check, guide proxy, or
startup endpoint. Network access is initiated only for a source the user adds,
its provider-hosted guide/artwork/media, or a future explicit external-browser
promotion action. Normal operation does not require a Klipa VPS.

## Scope

The v1 boundary is live TV only: M3U/M3U8, Xtream live channels, favorites,
single-stream playback, and local now/next XMLTV. VOD, series, recording,
multiview, pairing, cloud sync, plugins, and background services are out of
scope.

See [the complete specification](docs/spec.md), [product boundary](docs/product.md),
[architecture](docs/architecture.md), [security model](docs/security-model.md),
[native validation record](docs/native-validation.md), and
[dependency inventory](docs/dependencies.md). Private installer workflows are
documented in [packaging](docs/packaging.md), with reproducible SBOM and native
hash generation in [supply-chain evidence](docs/supply-chain.md). The exact
external-distribution gates are tracked in the [release checklist](docs/release-checklist.md).

## Code signing policy

Klipa Player desktop binaries are signed before external distribution through
a CI-provenance flow managed by SignPath. No binary built on a personal laptop
is ever signed and shipped.

Free code signing provided by [SignPath.io](https://about.signpath.io),
certificate by [SignPath Foundation](https://signpath.org).

Team roles:

- Authors/Reviewers: [KlipaTV](https://github.com/KlipaTV)
- Approvers: [KlipaTV](https://github.com/KlipaTV)

Privacy: this program will not transfer any information to other networked
systems unless specifically requested by the user or the person installing or
operating it.

Full signing flow, build-provenance requirements, and incident-response
procedure: see [Code signing policy](docs/code-signing-policy.md).

## License and branding

This project's first-party source code is licensed under the
**GNU Lesser General Public License v3.0 or later** — see `LICENSE`. The LGPL
was chosen so the commercial Klipa mobile app can link against shared
desktop components without becoming FOSS itself.

The Klipa name, logo, wordmark, and brand identifiers are **not** licensed
under the LGPL. Forks and modified redistributions must rename and rebrand
per `TRADEMARKS.md`. Nothing in this repository grants permission to imply
endorsement by Klipa.
