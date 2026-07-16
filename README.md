# Klipa Player for Windows

> [!CAUTION]
> Private local development. Do not publish, push to a public remote, submit to
> a store, or distribute binaries yet.

Klipa Player is a lightweight, open-source, local-first IPTV player for
Windows. It is designed for people who bring their own M3U/M3U8 playlist or
Xtream-compatible login. It includes no channels, subscriptions, ads, accounts,
or telemetry.

The product has a separate history and runtime from the Klipa mobile app. The
Windows UI shares Klipa's visual language, while its navigation and interaction
model are desktop-native.

## Current status

Private developer alpha:

- Windows-only Flutter project and local Git repository
- Klipa desktop shell, bounded M3U import, search and single-player vertical slice
- Masked Xtream login with bounded, live-only account/category/stream requests
- Compact category filtering and background-isolate playlist parsing
- Compact live controls for play/pause, mute, app-session volume, fit mode and
  native full screen, with focus-scoped keyboard shortcuts and playback-only
  auto-hide
- Race-safe channel replacement behind a small playback port, with teardown-first
  switching, bounded readiness, retry, and generic user-facing native errors
- Strict HTTP(S), redirect, size, header, protocol and private-network controls
- Versioned SQLite3MultipleCiphers schema, atomic snapshot writes, DPAPI
  key-sealing, reset primitives, and database/WAL/SHM leak tests
- Encrypted library save and startup restore on a background isolate; a failed
  save leaves the previous working snapshot active
- Stable multi-source identities, source/group filtering, rename, confirmed
  delete, and atomic refresh with `Ctrl+R`
- Encrypted per-channel favorites with responsive row toggles and a composable
  favorites-only filter; stable favorites survive source refresh
- Confirmed reset and missing/corrupt-key recovery are wired; broader
  distribution security gates remain open
- Native Windows debug build, DPAPI, encrypted database and libmpv smoke tests pass
- Native release build and an authorized private MPEG-TS playback smoke pass
- No remote configured and no public artifact

The Windows toolchain uses Flutter 3.44.6 stable, Visual Studio Build Tools
2022, the Desktop development with C++ workload, and Windows SDK 10.0.26100.

Native Windows validation also needs an NTFS-side worktree or build mirror.
Windows Flutter cannot create its package symlinks through this repository's
WSL UNC path. Run `tool/build_windows.ps1` from PowerShell to synchronize the
fixed private mirror and build there. No public remote is required.

## Development

Prerequisites:

- Flutter 3.44.6 stable
- Dart 3.11+
- Windows 11 or Windows 10 22H2 x64
- Visual Studio with Desktop development with C++ for native builds

```powershell
flutter pub get
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter build windows --release
```

Automated tests use only synthetic fixtures or legally documented
interoperability streams. An authorized private provider may be used for a
manual local smoke test through the masked UI, but never include its URL,
username, password, token, or authorization headers in source, commands, logs,
issues, tests, or screenshots.

On Windows, library data is stored below the app-specific directory in
`%LOCALAPPDATA%`. The database is encrypted as a whole and its random key is
sealed to the current Windows user with DPAPI. There is no plaintext fallback.

## Scope

The v1 boundary is live TV only: M3U/M3U8, Xtream live channels, favorites,
single-stream playback, and local now/next XMLTV. VOD, series, recording,
multiview, pairing, cloud sync, plugins, and background services are out of
scope.

See [the complete specification](docs/spec.md), [product boundary](docs/product.md),
[architecture](docs/architecture.md), [security model](docs/security-model.md),
[native validation record](docs/native-validation.md), and
[dependency inventory](docs/dependencies.md).

## License and branding

Source is provisionally licensed under Apache-2.0 for local development. The
Klipa name and logo are governed separately by [TRADEMARKS.md](TRADEMARKS.md).
Both are explicit pre-public review gates.
