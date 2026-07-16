# Security model and alpha risk register

This document records implementation reality. The broader target model is in
[spec.md](spec.md). Provider playlists, metadata, artwork, guide data, media
manifests, segments, subtitles, and decoder input are all untrusted.

## Enforced in the current tree

| Boundary | Current control |
|---|---|
| Playlist download | HTTP(S) only; trusted platform TLS; 10 s connect and 60 s total timeout; 5 manual redirects; no HTTPS downgrade; 25 MiB limit; HTML response rejection |
| Guide download | Direct to the configured provider only; same HTTP(S), DNS/private-network, redirect, TLS-downgrade, and HTML controls; 10 s connect, 120 s total timeout, and 32 MiB compressed-response limit; Xtream endpoint derived only from its saved origin; no fallback proxy or discovery host |
| Xtream import | Separate server, username and obscured-password fields; live-only API catalog; same-origin bounded M3U compatibility data intersected with live IDs; bounded JSON parsed off the UI isolate; sanitized source metadata; no persistence |
| Network destinations | URI validation, DNS classification, local/private target denial by default, explicit per-source LAN opt-in |
| M3U parsing | Background isolate; 25 MiB input, 64 KiB line, 8 KiB field and 100,000 channel limits; binary/NUL rejection; non-HTTP(S) streams skipped |
| XMLTV parsing/cache | Background event parser; 32 MiB compressed and 256 MiB decompressed limits; 500,000 retained-programme cap and bounded time window; strict UTF-8, nesting and field limits; DTD/entities rejected; explicit timezone conversion; exact provider guide-ID matching; atomic encrypted replacement preserves the last unexpired snapshot |
| Playlist directives | Only User-Agent, Referer and Origin are accepted; CR/LF values and privileged headers are dropped |
| Playback | At most one native player; teardown precedes replacement; stale events are rejected; first-media readiness is bounded and retryable; protocol allowlist is TCP, TLS, HTTP, HTTPS and crypto; libmpv config/scripts and URL extractors are disabled; no local file protocol; native errors are replaced with a generic user message |
| Remote artwork | Disabled. The alpha renders local initials, so an imported logo cannot trigger a nested request |
| Diagnostics | Common credentials, secret fields and complete URL paths/query/fragment data are redacted; no telemetry or remote logging |
| Local storage | Desktop imports, favorites, bounded navigation, provider guide IDs, and programme snapshots are saved in SQLite3MultipleCiphers; UI state receives source summaries and stable identities without locations or credentials; restored navigation is validated and never autoplays; refresh reads secrets transiently and publishes only after an atomic replacement succeeds; schema v3 preserves stable favorites and the last valid EPG snapshot; confirmed delete cascades all source data; a random 256-bit key is sealed with Windows DPAPI or Linux Secret Service; there is no plaintext fallback; tests scan the database, live WAL and SHM for seeded secrets and cover wrong/missing keys plus reset primitives |
| Secrets in source | No provider fixture, host, account, token, certificate bypass or signing credential is committed |

The installed app has no Klipa VPS dependency and does not contact Klipa on
install, launch, library browsing, playback, or EPG refresh. Provider network
traffic is direct from the app to the user-configured source. No analytics,
heartbeat, remote configuration, guide proxy, or background updater is present.

## Native validation completed

The private Windows build was validated locally on 2026-07-15 with Flutter
3.44.6, Dart 3.12.2, Visual Studio Build Tools 2022 17.14.36 and Windows SDK
10.0.26100. Debug and release bundles compiled, static analysis was clean,
DPAPI sealed and restored a random key for the current Windows user, the keyed
database reopened while an unkeyed SQLite connection failed, and the bundled
native media backend loaded and disposed with the restricted protocol list. A
private authorized Xtream catalog imported through the masked form and an
MPEG-TS channel played in the embedded player; unavailable entries failed with
a generic retryable message that did not expose native or provider details. See
[native-validation.md](native-validation.md).

## Distribution blockers

Encrypted persistence is active in the private alpha. Do not distribute a
binary until all blockers below close.

1. Close the media subresource policy gap. libmpv resolves HLS/DASH manifests,
   redirects, segments and subtitle URLs itself. The app currently validates
   the selected top-level URL, but cannot prove that nested media requests avoid
   loopback, link-local or private addresses.
2. Close the DNS time-of-check/time-of-use gap between app validation and
   libmpv resolution. A hostile hostname could change answers after validation.
3. Inventory and license-check every native binary and codec in the release
   bundle, record hashes, and establish a patch/update response window.
4. Fuzz the M3U and Xtream parsers and synthetic corrupt-media corpus under
   release builds.
5. Extend seeded-secret scanning to any future crash dumps and diagnostic logs.
   Transactional schema migration, confirmed reset/recovery, awaited player
   teardown, and database/WAL/SHM scanning are covered.
6. Configure a private security intake before making the repository public.

## Explicit non-goals

The application is not a DRM client, anonymity tool, malware scanner, provider
proxy, credential broker or secure media sandbox. A memory-safe Flutter shell
does not make native media decoding memory-safe; timely upstream patching and
constrained inputs remain required.
