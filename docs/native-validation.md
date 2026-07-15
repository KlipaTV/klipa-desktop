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
- The bundled native media backend loads and disposes while scripts, URL
  extractors, and non-required protocols stay disabled.
- Widget and platform tests cover separate masked Xtream credentials, live-only
  endpoint selection, same-origin M3U compatibility mapping restricted to live
  IDs, bounded M3U/Xtream input, private-network opt-in, and URL path/query
  redaction.
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
