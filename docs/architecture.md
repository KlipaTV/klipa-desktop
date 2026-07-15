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
- event-based XML parsing for XMLTV
- small reviewed Windows interop only where Flutter lacks an API

## Persistence gate

No source, channel URL, credential, or guide URL may be persisted until all of
these are implemented and tested:

1. Random 256-bit database key generation.
2. DPAPI sealing/unsealing scoped to the current Windows user.
3. SQLite3MultipleCiphers keying before schema access.
4. Encrypted journal/WAL verification.
5. Reset and corrupted/missing-key recovery.
6. Tests showing secrets are absent from database bytes and diagnostics.

The key-protection and encrypted-database primitives now exist. DPAPI,
SQLite3MultipleCiphers and package smoke tests pass on the actual Windows native
build. Imports remain memory-only until WAL/SHM secret scanning, schema
migration, and reset/recovery UX are implemented and exercised.
