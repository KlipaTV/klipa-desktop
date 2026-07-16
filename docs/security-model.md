# Security model and alpha risk register

This document records implementation reality. The broader target model is in
[spec.md](spec.md). Provider playlists, metadata, artwork, guide data, media
manifests, segments, subtitles, and decoder input are all untrusted data. The
user-configured provider or local playlist is, however, trusted to choose media
network destinations. This distinction is required by the lightweight v1
playback architecture and is disclosed before every source import.

## Enforced in the current tree

| Boundary | Current control |
|---|---|
| Playlist download | HTTP(S) only; trusted platform TLS; 10 s connect and 60 s total timeout; 5 manual redirects; no HTTPS downgrade; 25 MiB limit; HTML response rejection |
| Guide download | Direct to the configured provider only; same HTTP(S), DNS/private-network, redirect, TLS-downgrade, and HTML controls; 10 s connect, 120 s total timeout, and 32 MiB compressed-response limit; Xtream endpoint derived only from its saved origin; no fallback proxy or discovery host |
| Xtream import | Separate server, username and obscured-password fields; live-only API catalog; same-origin bounded M3U compatibility data intersected with live IDs; bounded JSON parsed off the UI isolate; sanitized source metadata; no persistence |
| App-managed network destinations | URI validation, DNS classification, local/private target denial by default, explicit per-source LAN opt-in; applies to playlist, Xtream and XMLTV requests handled by the bounded Dart client |
| M3U parsing | Background isolate; 25 MiB input, 64 KiB line, 8 KiB field and 100,000 channel limits; binary/NUL rejection; non-HTTP(S) streams skipped |
| XMLTV parsing/cache | Background event parser; 32 MiB compressed and 256 MiB decompressed limits; 500,000 retained-programme cap and bounded time window; strict UTF-8, nesting and field limits; DTD/entities rejected; explicit timezone conversion; exact provider guide-ID matching; atomic encrypted replacement preserves the last unexpired snapshot |
| Playlist directives | Only User-Agent, Referer and Origin are accepted; CR/LF values and privileged headers are dropped |
| Playback | At most one native player; teardown precedes replacement; stale events are rejected; first-media readiness is bounded and retryable; protocol allowlist is TCP, TLS, HTTP, HTTPS and crypto; libmpv config/scripts, URL extractors, unsafe playlists, cookies, and external-file autoload are disabled; TLS verification is forced; network operations use a 30-second timeout; no local file protocol; native errors are replaced with a generic user message; libmpv may resolve HLS/DASH references and redirects outside the Dart destination validator |
| Remote artwork | Disabled. The alpha renders local initials, so an imported logo cannot trigger a nested request |
| Diagnostics | Common credentials, secret fields and complete URL paths/query/fragment data are redacted; no telemetry or remote logging |
| Local storage | Desktop imports, favorites, bounded navigation, provider guide IDs, optional M3U guide URLs, and programme snapshots are saved in SQLite3MultipleCiphers; UI state receives source summaries and stable identities without locations or credentials; restored navigation is validated and never autoplays; refresh reads secrets transiently and publishes only after an atomic replacement succeeds; schema v4 preserves stable favorites and the last valid EPG snapshot; confirmed delete cascades all source data; a random 256-bit key is sealed with Windows DPAPI or Linux Secret Service; there is no plaintext fallback; tests scan the database, live WAL and SHM for seeded secrets and cover wrong/missing keys plus reset primitives |
| Secrets in source | No provider fixture, host, account, token, certificate bypass or signing credential is committed |

The installed app has no Klipa VPS dependency and does not contact Klipa on
install, launch, library browsing, playback, or EPG refresh. Provider network
traffic is direct from the app to the user-configured source. No analytics,
heartbeat, remote configuration, guide proxy, or background updater is present.

## Accepted lightweight playback boundary

Klipa keeps HLS/DASH compatibility without adding a local media proxy or a
cross-platform network sandbox. The app validates the selected top-level stream
immediately before playback, but libmpv then owns media redirects, manifest
references, segment retrieval, and later DNS resolution. Consequently, the app
cannot guarantee that those nested requests avoid loopback, link-local, or
private addresses, and top-level DNS validation is not DNS pinning.

Every URL, Xtream, and local-playlist import warns that the source must be
trusted to choose network destinations. This is a trust decision about where
the player connects, not about the safety of returned bytes: all metadata,
manifests, and media remain bounded or processed as untrusted input wherever
the architecture permits. Users should not import playlists or accounts from
unknown parties. Closing this residual destination risk would require removing
adaptive-stream support or adding a validating proxy/sandbox, neither of which
is in the lightweight v1 scope.

## Native validation completed

The private Windows build was validated locally on 2026-07-16 with Flutter
3.44.6, Dart 3.12.2, Visual Studio Build Tools 2022 17.14.36 and Windows SDK
10.0.26100. Debug and release bundles compiled, static analysis was clean,
DPAPI sealed and restored a random key for the current Windows user, the keyed
database reopened while an unkeyed SQLite connection failed, and the bundled
native media backend loaded and disposed with the restricted protocol list. A
private authorized Xtream catalog imported through the masked form and an
MPEG-TS channel played in the embedded player; unavailable entries failed with
a generic retryable message that did not expose native or provider details. See
[native-validation.md](native-validation.md).

## Remaining public distribution blockers

Encrypted persistence is active in the private release candidate. Do not distribute a
binary until all blockers below close.

1. The release tooling now records every native file hash/version, the locked
   source SBOM, dynamic Linux dependencies, and Flutter notices. Complete the
   Windows libmpv/FFmpeg codec and license provenance review and establish a
   patch/update response window; the bundled DLL identifies as mpv 0.36.
2. Deterministic release fuzzing covers M3U, XMLTV, and Xtream parsing. Add a
   synthetic corrupt-media corpus against the native decoder on the supported
   GPU/OS matrix.
3. Extend seeded-secret scanning to any future crash dumps and diagnostic logs.
   Transactional schema migration, confirmed reset/recovery, awaited player
   teardown, and database/WAL/SHM scanning are covered.
4. Configure a private security intake before making the repository public.

## Explicit non-goals

The application is not a DRM client, anonymity tool, malware scanner, provider
proxy, credential broker or secure media sandbox. A memory-safe Flutter shell
does not make native media decoding memory-safe; timely upstream patching and
constrained inputs remain required.
