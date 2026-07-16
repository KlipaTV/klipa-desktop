# Native Windows validation

**Status:** Private local evidence; not a release approval

**Last run:** 2026-07-15

## Environment

- Windows 11 x64 under the project's NTFS build mirror
- Flutter 3.44.6 stable
- Dart 3.12.2
- Visual Studio Build Tools 2022 17.14.36
- Desktop development with C++ workload
- Windows SDK 10.0.26100

## Reproduction

From PowerShell, run:

```powershell
.\tool\build_windows.ps1 -Configuration debug
.\tool\build_windows.ps1 -Configuration release
```

The script synchronizes the fixed private NTFS mirror, excluding Git and build
state, then runs package resolution, strict analysis, a native Windows build,
and the complete Windows test suite against the built native DLL bundle. It has
no remote or publishing step.

## Evidence obtained

- The native Windows debug and release executables and plugin bundles compile
  successfully.
- Static analysis completes with no issues.
- A DPAPI round trip seals and restores random bytes for the current user.
- A SQLite3MultipleCiphers database reopens with its key, rejects an unkeyed
  SQLite connection, and does not expose a seeded marker in the closed database
  bytes.
- Schema v2 migrates from the legacy metadata schema, writes 10,000-channel
  snapshots through prepared statements, rolls back interrupted refreshes,
  preserves stable favorites, and keeps seeded secrets absent from the live
  database, WAL and SHM files.
- The runtime library store saves atomically off the UI isolate, seals its key
  with DPAPI, closes, reopens through a fresh store instance, and restores the
  source and playable channel. Controller tests prove state is published only
  after the save succeeds and that a failed save preserves the prior snapshot.
- Reset requires an enumerated confirmation, awaits native player disposal,
  removes the database/WAL/SHM and sealed-key files, and returns to onboarding.
  A startup key/read failure exposes the same recovery action.
- Source locations and credentials are absent from UI source summaries.
  Stable-identity refresh, rename and confirmed cascading delete are covered;
  failed download/parse/save paths retain the prior source snapshot, and a
  surviving channel selection is rebound to the refreshed channel object.
- Favorite toggles are encrypted, publish only after storage succeeds, compose
  with source/category/search filters, survive stable refresh identities, and
  are removed by source/channel cascades.
- Last source/group/channel navigation writes are ordered and encrypted. Restore
  discards stale identities, leaves the player stopped, and opens the exact
  surviving source/channel pair only after an explicit Resume click.
- The bundled native media backend loads and disposes while scripts, URL
  extractors, and non-required protocols stay disabled.
- Deterministic lifecycle tests cover first-media timeout and retry, a hung open
  command, teardown-before-replacement, and rejection of stale completion and
  error events during rapid channel changes. Native failures are mapped to a
  generic retryable message rather than exposing provider or libmpv details.
- The profile runner entered monitor-aware borderless full screen through the
  native window channel and `F`, then `Esc` restored the prior framed window
  placement. The same synthetic unreachable stream kept the visible overlay in
  `BUFFERING` state instead of incorrectly auto-hiding it. The check used a
  local test playlist and no provider data.
- Widget and platform tests cover separate masked Xtream credentials, live-only
  endpoint selection, same-origin M3U compatibility mapping restricted to live
  IDs, background-isolate playlist parsing, bounded M3U/Xtream input,
  source/category/search/favorites filtering, compact and expanded source
  management,
  private-network opt-in, URL path/query redaction,
  playback control states, and focus-scoped single-letter shortcuts.
- An authorized private, multi-thousand-channel catalog imported through the
  masked Xtream form without entering a credential-bearing URL. A matching
  same-origin M3U path played as MPEG-TS in the embedded player. Unavailable
  entries showed a redacted error, and switching back to the working entry
  recovered playback. No provider identifier or credential is retained in this
  repository or validation record.

## Still required before distribution

- HLS coverage and broader repeated channel-change testing across the Intel,
  AMD and NVIDIA hardware matrix; the current MPEG-TS evidence is one machine
  and one authorized provider.
- Automated secret scanning of live database WAL/SHM files, crash dumps and
  application diagnostics.
- Nested media request and DNS-rebinding controls or a documented constrained
  architecture that closes those gaps.
- Release-mode fuzzing, exact native binary hashes, codec/license inventory,
  SBOM, signing and clean-machine packaging tests.
