# Architecture

The implementation stays intentionally shallow:

```text
Flutter view -> Riverpod controller -> concrete repository/service
                                      -> media player port
```

There is no event bus, service locator, generic repository base, use-case class
per action, webview, local server, plugin system, or background scheduler.

## Selected stack

- Flutter stable for the Windows UI
- Riverpod stable APIs for state and dependency boundaries
- media_kit/libmpv behind `VideoPlayerPort`
- direct SQLite FFI using SQLite3MultipleCiphers
- one random database key sealed to the Windows user with DPAPI
- dart:io HttpClient behind a bounded, redirect-aware client
- Dart isolates for bounded M3U and Xtream JSON parsing off the UI thread
- event-based XML parsing for XMLTV
- small reviewed Windows interop only where Flutter lacks an API

`PlayerPane` depends only on the small `VideoPlayerPort` surface. Each channel
replacement invalidates older callbacks, disposes the prior native player
before creating the next one, and has a bounded first-media readiness window.
This keeps native lifecycle behavior directly testable without adding a general
media abstraction layer.

## Persistence gate

No source, channel URL, credential, or guide URL may be persisted until all of
these are implemented and tested:

1. Random 256-bit database key generation.
2. DPAPI sealing/unsealing scoped to the current Windows user.
3. SQLite3MultipleCiphers keying before schema access.
4. Encrypted journal/WAL verification.
5. Reset and corrupted/missing-key recovery.
6. Tests showing secrets are absent from database bytes and diagnostics.

The key-protection and encrypted-database primitives are wired into the Windows
runtime. Schema v2 uses explicit transactional migration, separates list
metadata from source and channel secrets, replaces source snapshots atomically,
preserves stable favorites, and has database/WAL/SHM secret scans plus reset
primitives. Save and startup restore run off the UI isolate. DPAPI,
SQLite3MultipleCiphers, a fresh-store close/reopen cycle, and package smoke tests
pass on the actual Windows native build. Reset waits for native player teardown,
then removes the encrypted database, sidecars, sealed key, and interrupted key
replacement. A missing or unreadable key routes startup to the same confirmed
recovery flow. The broader distribution blockers in the security model remain.
