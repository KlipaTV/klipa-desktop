# Product boundary

Klipa Player is a fast Windows live-TV player that earns trust first and
promotes Klipa mobile without behaving like adware.

## Principles

- Useful before promotional.
- No channels, accounts, ads, tracking, or background service.
- Data and guide processing stay on the PC.
- Desktop-native keyboard, mouse, resize, focus, Narrator, and high-DPI behavior.
- One process, one window, one encrypted database, one HTTP client, and one
  player instance.
- Current stable dependencies with a maximum of twelve direct runtime packages.

## Alpha outcome

A user can import a synthetic or personally supplied M3U/M3U8 source, search
and filter its live channels, select one, and play it in a Klipa-branded desktop
shell. On Windows, successful imports are committed atomically to the encrypted
per-user library and restored on the next launch without autoplaying an
arbitrary channel. Multiple sources can be filtered, renamed, refreshed, and
deleted without placing their provider locations or credentials in UI state.
The last valid source, group, and channel context is restored locally, but
media resumes only after an explicit user click.

## Security boundary

User-entered provider content is untrusted. The app applies byte, entry, line,
redirect, timeout, scheme, header, and private-network limits to its own import
and guide requests before parsing or fetching. It never executes playlist
content, loads libmpv scripts, disables TLS verification, or forwards arbitrary
headers.

The lightweight v1 player trusts each user-added provider or local playlist to
choose media network destinations. libmpv may follow HLS/DASH references and
repeat DNS resolution outside the app validator, so every import path discloses
that limitation. A source is trusted for destinations, while its metadata and
media bytes remain untrusted input.

The native decoder remains the largest attack surface. Native media artifacts
must be pinned, inventoried, and reviewed before any binary is distributed.

## Promotion boundary

Klipa mobile may appear only as a secondary onboarding link, compact library
footer link, About link, and website/README link. No modal, timer, notification,
or playback overlay may promote the mobile app.
