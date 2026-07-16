# Architecture

The implementation stays intentionally shallow:

```text
Flutter view -> Riverpod controller -> concrete repository/service
                                      -> media player port
```

There is no event bus, service locator, generic repository base, use-case class
per action, webview, local server, plugin system, or background scheduler.

## Selected stack

- Flutter stable for the Windows and Linux UI
- Riverpod stable APIs for state and dependency boundaries
- media_kit/libmpv behind `VideoPlayerPort`
- direct SQLite FFI using SQLite3MultipleCiphers
- one random database key sealed with Windows DPAPI or Linux Secret Service
- dart:io HttpClient behind a bounded, redirect-aware client
- Dart isolates for bounded M3U, Xtream JSON, and XMLTV parsing off the UI thread
- event-based plain/gzip XMLTV parsing with DTD/entity rejection
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
runtime. Schema v4 uses explicit transactional migration, separates list
metadata from source and channel secrets, replaces source snapshots atomically,
preserves stable favorites, and stores provider guide identity plus bounded EPG
snapshots. Programme replacement is transactional, so a failed refresh retains
the previous unexpired guide. Exact `(source, guide ID)` joins prevent channel
name guessing. Database/WAL/SHM secret scans and reset primitives are covered.
Save and startup restore run off the UI isolate. DPAPI,
SQLite3MultipleCiphers, a fresh-store close/reopen cycle, and package smoke tests
pass on the actual Windows native build. Reset waits for native player teardown,
then removes the encrypted database, sidecars, sealed key, and interrupted key
replacement. A missing or unreadable key routes startup to the same confirmed
recovery flow. The broader distribution blockers in the security model remain.

UI state receives only safe source summaries. Provider locations, usernames,
and passwords remain in the encrypted source-secret table and are loaded into a
short-lived refresh request only. Refresh downloads and parses first, commits a
complete replacement transaction second, and publishes the new UI snapshot
last; any failure leaves the prior playable snapshot and stable selection
untouched.

Guide refresh follows the same commit-before-publish rule. Xtream XMLTV is
downloaded directly from the saved provider, parsed off the UI isolate, and
atomically committed before schedules are published. Failure leaves playback
and the previous unexpired schedule usable. Startup reads the encrypted cache
only and never refreshes over the network.

## Runtime network boundary

Install and application startup do not perform network requests. The runtime
contains no Klipa API client, guide proxy, telemetry sender, remote logger, or
automatic update checker. Playlist, guide, artwork, and media requests are
allowed only toward user-configured provider locations after the relevant user
action. Xtream XMLTV is derived from the saved provider origin; M3U XMLTV
requires an explicit URL and is never guessed or discovered. A promotional
Klipa link, if added later, must be an explicit action
that opens the system browser and must not become an in-app service dependency.

The bounded Dart client validates every app-managed destination and redirect.
Playback is the deliberate exception: after top-level validation, libmpv may
follow HLS/DASH redirects, manifests, segments, and later DNS answers itself.
Every import path therefore requires the user to trust that source to select
media network destinations. Returned media and metadata remain untrusted. v1
does not add a local validating proxy or OS network sandbox.

Favorite state is represented in UI memory only by non-secret source/channel
identities. A toggle is committed through the encrypted store before it is
published to the UI. Refresh prunes favorites only when their stable channel
identity disappears, while source deletion removes them through the database
foreign-key cascade.

The last source, group, and channel identity are stored together as one bounded
encrypted navigation record. Restore validates every identity against the
current library, restores filters, and exposes the surviving last channel only
as an explicit Resume action. Startup never creates a media player or contacts
a stream until the user activates a channel.
