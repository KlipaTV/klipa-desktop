# Klipa Player for Desktop — product and technical specification

**Status:** Private release candidate

**Product:** Klipa Player

**Private repository:** `klipa-desktop`

**Platforms:** Windows 11, Windows 10 22H2, and supported Debian/Ubuntu, x64

**Document owner:** Klipa

**Last updated:** 2026-07-15

## 1. Executive summary

Klipa Player is a free, privately developed, local-first IPTV player for
Windows and Linux. It
lets people bring their own M3U/M3U8 playlist or Xtream-compatible login,
browse live channels, see local now/next guide data, and start playback with as
little ceremony as possible.

The player has two jobs, in this order:

1. Be a small, trustworthy desktop IPTV player that people willingly use and
   recommend.
2. Introduce those users to the full Klipa mobile and Android TV app without
   turning the Windows player into an advertisement.

The desktop player is a separate private product, not a new target inside the
Klipa mobile repository. It lives in an independent repository with its own
history and has no source or runtime dependency on the mobile app. Concepts and
code may cross repository boundaries only after ownership, license, secret, and
platform reviews. Private infrastructure, credentials, store tooling, and
unrelated history must not cross those boundaries.

The v1 product is intentionally live-TV-only. It does not include VOD, series,
multiview, recording, cloud sync, pairing, reminders, or accounts. Those
boundaries keep the player fast, make the codebase understandable, and
leave the mobile/TV app with a clear richer-product story.

## 2. Product definition

### 2.1 Positioning

> A fast, local-first IPTV player for Windows and Linux. Bring your own M3U or Xtream
> login. No channels, no account, no ads, and no tracking.

Short store description:

> Lightweight M3U and Xtream live TV player. Local-first, ad-free, and built by
> Klipa.

### 2.2 Product principles

1. **Useful before promotional.** The app must remain a good player if every
   link to the mobile app is removed.
2. **Fast path to video.** A new user should understand the first screen and be
   able to start importing within ten seconds.
3. **Local-first by default.** Playlists, credentials, favorites, guide data,
   and settings stay on the PC. The app has no Klipa account and no analytics
   SDK.
4. **Desktop-native behavior.** Mouse, keyboard, resizing, multiple displays,
   high-DPI scaling, file drag-and-drop, and Windows conventions are product
   requirements, not later polish.
5. **Small surface area.** One player, live channels, local guide data, and a
   restrained set of settings. Every new feature must justify its binary,
   runtime, UI, and maintenance cost.
6. **Modern means stable and small.** Use current stable releases and native
   capabilities with a strict dependency budget. Do not use preview frameworks,
   an embedded web application, or abstraction layers without a concrete need.
7. **Transparent in practice.** Reproducible internal builds, a security policy,
   dependency notices, privacy documentation, and releasable CI are part of the
   product even while the source remains private.
8. **No content business.** Klipa supplies software, not channels, playlists,
   provider recommendations, or access to third-party media.

### 2.3 Goals

- Make the Klipa name discoverable among Windows and IPTV users.
- Earn trust through useful software and transparent privacy.
- Send qualified, user-initiated traffic to the Klipa mobile/TV app.
- Reuse proven Klipa parsing and playback knowledge without exposing or
  coupling the private mobile repository.
- Keep the product maintainable by a small Klipa team.

### 2.4 Non-goals

- Matching every feature in the mobile or Android TV app.
- Bundling, selling, discovering, ranking, or recommending IPTV providers or
  channels.
- Circumventing DRM, geo-restrictions, provider limits, or access controls.
- Supporting Windows 8 or older or macOS in v1.
- Supporting VOD, films, series, catch-up, timeshift, DVR, downloads, or
  recording in v1.
- Multiview, casting, phone-to-PC pairing, cloud sync, remote control, plugins,
  or extensions in v1.
- Background services, a resident tray process, an embedded browser, or an
  always-running updater.
- Monetization, ads, premium tiers, donations in the UI, or sponsored links at
  launch.

## 3. Audience and primary journeys

### 3.1 Primary users

- A Windows user who received an M3U URL and wants to watch live TV without
  learning a complex media player.
- A user with an Xtream-compatible server, username, and password who wants a
  clear login flow and a searchable live-channel list.
- A technical or privacy-conscious user who wants clear network boundaries,
  no account, and no telemetry.
- An existing Klipa user who wants a simple desktop companion without syncing
  their library to a Klipa server.

### 3.2 Core user stories

- As a new user, I can paste an M3U URL, open an M3U/M3U8 file, or enter Xtream
  credentials and see channels without configuring the player first.
- As a returning user, I land on my last library and can resume watching with
  one click.
- As a user with a large playlist, I can search and filter by group without UI
  stalls.
- As a keyboard user, I can import, browse, play, control volume, and enter or
  exit full screen without a mouse.
- As a privacy-conscious user, I can see exactly what leaves my PC and can use
  the player without sending data to Klipa.
- As an authorized developer, I can clone the private repository, run tests,
  build releases for Windows and Linux, and understand the boundaries from the
  README.

### 3.3 Canonical first-run journey

1. Launch into a single welcome screen with the Klipa mark, one-sentence value
   proposition, and three import actions: **Paste playlist URL**, **Open M3U
   file**, and **Use Xtream login**.
2. Enter or choose a source. The app validates the input without clearing the
   form on failure.
3. Show determinate progress where possible: connecting, downloading, parsing,
   then saving.
4. Open the desktop library with the first playable live channel selected but
   do not autoplay audio until the user activates a channel.
5. On activation, play in the right-hand pane. Double-clicking the video or
   pressing `F`/`F11` enters full screen.
6. Preserve the imported library, current filters, last channel, window bounds,
   and volume for the next launch.

## 4. Scope by release

### 4.1 Phase 0 — feasibility and private-repo foundation

Phase 0 must complete before product implementation is treated as committed.

- Create a separate private repository with an independently reviewable history.
- Confirm the `Klipa Player` desktop product identity and private repository
  boundary.
- Complete a Windows playback spike using Flutter and the candidate
  `media_kit`/libmpv stack on Intel, AMD, and NVIDIA hardware.
- Prove the selected stack stays within the section 11 size, startup, memory,
  and dependency budgets. A framework choice that misses them does not advance
  because it is convenient to prototype.
- Verify HLS and MPEG-TS playback, full screen, resize behavior, hardware decode
  fallback, teardown, and repeated channel changes on Windows 10 and 11.
- Audit the exact native binaries, codec configuration, transitive licenses,
  notices, and redistribution obligations. The Dart package's license alone is
  not sufficient evidence for bundled libmpv/FFmpeg binaries.
- Validate the encrypted SQLite build and DPAPI key lifecycle on clean install,
  upgrade, Windows-user separation, reset, and uninstall. Confirm credentials
  do not appear in the database, journal/WAL, key file, logs, or app-generated
  diagnostic output.
- Decide the exact Windows build floor supported by the selected Flutter and
  native playback versions.
- Scan every proposed file for credentials, private hosts, internal endpoints,
  and private comments before it crosses a repository boundary.
- Maintain license, trademark, security, support, and dependency documentation
  before any external distribution.

Exit criterion: a clean CI build plays the fixture streams on the hardware
matrix, the dependency audit has no unresolved release blocker, and repository
boundaries contain only their intended material.

### 4.2 v0.1 — developer alpha

- Windows x64 debug and release builds.
- Remote M3U/M3U8 import and local file import.
- Xtream login for live categories and live streams only.
- Desktop channel browser, search, category filter, and in-pane playback.
- Play/pause, volume, mute, retry, fit mode, and full screen.
- Local library persistence and source refresh.
- Encrypted SQLite with a DPAPI-sealed per-user database key.
- Redacted diagnostics suitable for GitHub issue reports.
- Unit, widget, and Windows build CI.

The alpha may be shared privately with explicitly approved technical testers.
It is not marketed as the stable consumer release.

### 4.3 v0.5 — private beta

- Favorites and stable identity across source refreshes.
- Local XMLTV download, parse, cache, and now/next display.
- Drag-and-drop M3U/M3U8 import.
- English and Spanish UI.
- Complete keyboard navigation, Narrator labels, high-contrast support, and
  200% text scaling.
- Responsive desktop layouts and multi-monitor/high-DPI validation.
- Branded About and mobile-app links.
- Automated release artifacts, checksums, dependency notices, and SBOM.

### 4.4 v1.0 — stable launch

- Microsoft Store MSIX as the primary consumer distribution.
- Approved desktop downloads with checksums, SBOM, and portable builds where
  appropriate. Source publication is not required.
- Store listing, privacy page, screenshots, support page, and legal disclaimer.
- Crash-free clean-install, upgrade, and uninstall validation.
- All release acceptance criteria in section 15 passing.
- A dedicated `klipa.tv/windows/` landing page and first-party mobile referral
  route.

### 4.5 Explicitly deferred

The following are not silently included in v1 even if the private mobile app
already has related code:

- VOD, films, series, catch-up, timeshift, recording, and downloads.
- Multiview and picture-in-picture.
- EPG grid, reminders, or background notifications. v1 shows now/next only.
- Mobile/TV pairing or library sync.
- Multiple simultaneous players.
- Automatic background updates outside the Microsoft Store.
- Windows on ARM. Reconsider only after the playback binary and CI matrix are
  proven on ARM64.
- Custom themes, skins, scripting, and plugins.

## 5. Functional requirements

Requirements use `WIN-<area>-<number>` as stable identifiers.

### 5.1 Source import and management

- **WIN-IMP-001:** The empty state shall present remote M3U/M3U8 URL, local
  M3U/M3U8 file, and Xtream login as equal first-class import paths.
- **WIN-IMP-002:** The remote URL form shall accept `http` and `https`. Cleartext
  `http` remains supported because many user-owned IPTV servers require it, but
  the form shall warn that credentials and content may be visible on the
  network before the first cleartext import.
- **WIN-IMP-003:** The Xtream form shall collect server URL, username, and
  password separately. It shall normalize trailing slashes and common pasted
  formats without showing a generated credential-bearing URL.
- **WIN-IMP-004:** Xtream import shall request only account validation, live
  categories, live streams, and the derived XMLTV guide endpoint. It shall not
  fetch VOD or series catalogs in v1.
- **WIN-IMP-005:** The local file flow shall support the file picker,
  `Ctrl+O`, command-line file activation, and drag-and-drop for `.m3u` and
  `.m3u8` files.
- **WIN-IMP-006:** The parser shall support UTF-8 with or without BOM and a
  documented fallback for common legacy playlist encodings. A malformed entry
  shall not invalidate the rest of an otherwise usable playlist.
- **WIN-IMP-007:** Supported metadata shall include channel name, `tvg-id`,
  `tvg-name`, `tvg-logo`, `group-title`, channel number where present,
  `#EXTVLCOPT` user agent/referrer, and safe `#KODIPROP` stream headers.
- **WIN-IMP-008:** The app shall support multiple sources, each with rename,
  refresh, and delete actions. Delete shall explain that it removes that
  source's cached channels, favorites, and guide data.
- **WIN-IMP-009:** Refresh shall update a source atomically. A failed refresh
  leaves the previous working snapshot available.
- **WIN-IMP-010:** Favorites and last-channel state shall survive refresh when
  stable channel identity can be matched.
- **WIN-IMP-011:** Import errors shall distinguish invalid input,
  authentication failure, subscription expiry when reported by the provider,
  timeout, DNS/network failure, TLS failure, HTTP refusal, HTML returned instead
  of a playlist, empty playlist, and storage failure.
- **WIN-IMP-012:** Error and diagnostic text shall redact username, password,
  token, authorization values, credential-bearing path segments, and sensitive
  query parameters.

### 5.2 Library and browsing

- **WIN-LIB-001:** The default desktop layout shall expose sources/groups,
  channels, and video without requiring tab navigation at normal desktop
  widths.
- **WIN-LIB-002:** Users shall be able to filter by source and playlist group,
  search channel names, and show favorites only.
- **WIN-LIB-003:** Search shall be case-insensitive, accent-tolerant where the
  locale permits, and responsive for a 50,000-channel library.
- **WIN-LIB-004:** Each channel row shall show the channel logo or a deterministic
  fallback, channel name, group when useful, favorite state, and now/next
  programme when available.
- **WIN-LIB-005:** Channel logos shall load lazily, have request and decoded-size
  limits, use a bounded disk cache, and never block channel-list scrolling.
- **WIN-LIB-006:** A single click selects and starts a channel. Enter activates
  the focused channel. Double-clicking the active video enters full screen.
- **WIN-LIB-007:** The app shall remember the last selected source, group,
  channel, volume, mute state, fit mode, window bounds, and maximized state.
- **WIN-LIB-008:** If the last channel no longer exists, the app shall open the
  library without autoplaying an arbitrary replacement.

### 5.3 Playback

- **WIN-PLY-001:** v1 shall guarantee playback support for HLS and MPEG-TS over
  HTTP/HTTPS using the pinned native media stack.
- **WIN-PLY-002:** v1 shall reject RTSP, RTMP, RTP, UDP, `data:`, `file:`, and
  other stream schemes. Add a protocol only through a spec change, threat
  review, maintained fixture, and release test. Opening a local M3U file does
  not grant its channel entries local-file access.
- **WIN-PLY-003:** DRM-protected playback, browser cookies, provider web login,
  and certificate-verification bypass are unsupported.
- **WIN-PLY-004:** The player shall expose play/pause, retry, mute, volume,
  aspect/fit mode, stream status, and full-screen controls. Live streams shall
  not show a fake seek bar.
- **WIN-PLY-005:** Controls shall auto-hide only while video is playing and
  reappear on pointer movement, keyboard input, buffering, pause, or error.
- **WIN-PLY-006:** The app shall create at most one native player instance and
  release it on channel replacement and application exit without leaving a
  child process or locked file.
- **WIN-PLY-007:** Hardware decoding shall default to automatic safe selection
  with software fallback. An advanced diagnostic setting may disable hardware
  decode for troubleshooting; codec-specific tuning is not exposed in v1.
- **WIN-PLY-008:** A channel-change timeout shall result in a retryable, redacted
  error while keeping the channel list usable.
- **WIN-PLY-009:** Playlist header directives are limited to `User-Agent`,
  `Referer`, and `Origin` in v1, with CR/LF and length validation. `Host`,
  `Connection`, `Proxy-*`, `Content-Length`, `Authorization`, `Cookie`, and
  unknown headers are rejected. Allowed headers are stripped on cross-origin
  redirects.
- **WIN-PLY-010:** Audio volume shall integrate with the app session in Windows
  Volume Mixer. The app shall not change the system master volume.

### 5.4 Local EPG

- **WIN-EPG-001:** The user may attach an XMLTV URL to an M3U source. An Xtream
  source may derive its XMLTV URL from the same credentials.
- **WIN-EPG-002:** XMLTV retrieval and parsing shall happen locally. No guide
  URL, provider credential, or guide payload is sent to Klipa infrastructure.
- **WIN-EPG-003:** The parser shall support plain XML and gzip-compressed XMLTV,
  process it as a stream or isolate-backed job, and enforce compressed and
  decompressed size limits.
- **WIN-EPG-004:** Guide records shall match `channel id` to playlist `tvg-id`
  exactly before any documented fallback. Ambiguous fuzzy matching is not
  allowed.
- **WIN-EPG-005:** v1 shall display current and next programme only. It shall not
  ship a full schedule grid or reminders.
- **WIN-EPG-006:** Refresh occurs on import, on explicit user action, and at a
  bounded interval while the app is open. The app shall not install a
  background task for EPG refresh.
- **WIN-EPG-007:** A guide failure shall not block playlist refresh or playback.
  The last successful unexpired guide snapshot remains available.

### 5.5 Settings and diagnostics

- **WIN-SET-001:** Settings shall include language, system/light/dark theme,
  playback fit, hardware-decode troubleshooting toggle, logo-cache clear,
  source management, privacy, licenses, and About.
- **WIN-SET-002:** English and Spanish ship in v1. Localization architecture
  shall permit community locales without changing feature code.
- **WIN-SET-003:** Diagnostics shall be off by default and local only. A user may
  explicitly copy a redacted environment report containing app version,
  Windows version, architecture, renderer, playback engine version, non-secret
  error codes, and recent bounded log entries.
- **WIN-SET-004:** The app shall not integrate a remote crash reporter or usage
  analytics SDK in v1.
- **WIN-SET-005:** **Reset app data** shall require confirmation, enumerate what
  will be deleted, close the player, remove library/cache/credentials, and
  return to onboarding.

## 6. Desktop UX specification

### 6.1 Main layout

At widths of 1,100 logical pixels or more, use a three-pane shell:

```text
+----------------------+----------------------------+---------------------------+
| Klipa Player         | Search channels...         |                           |
|                      |                            |                           |
| Sources              | [logo] Channel name   star|                           |
|  All channels        | Now: programme             |       active video        |
|  Source A            |                            |                           |
|                      | [logo] Channel name   star|                           |
| Groups               | Next: programme            |                           |
|  News                |                            +---------------------------+
|  Sports              |                            | channel / status / controls|
|  ...                 |                            | now + next                 |
|                      |                            |                           |
| Klipa on mobile  ->  |                            |                           |
+----------------------+----------------------------+---------------------------+
     220-260 px                  320-400 px                   flexible
```

- At 900–1,099 px, collapse the source/group rail into a toolbar drawer while
  preserving channel list plus player.
- The minimum supported window is 840×560 logical pixels. Below that size the
  window does not continue shrinking.
- Full screen contains video and overlay only. `Esc` returns to the exact prior
  window state.
- The desktop shell must be selected by platform/input profile, not by a broad
  `width > 1024` rule. A wide Windows window must never become an Android-TV
  remote shell.

### 6.2 Visual direction

The Windows player should be recognizable as Klipa before the wordmark is read.
Copy the approved brand tokens into the new repository as owned source; do not
create a runtime dependency on the mobile repository.

- Preserve Klipa's core dark palette: ink `#0E0E0E`, raised ink `#1A1A1A` and
  `#252525`, primary text `#E8E8E8`, secondary text `#CCCCCC`, muted text
  `#8C8C8C`, indigo `#6C5CE7`, success `#51CF66`, and accessible live red
  `#D32F2F`.
- Preserve the Inter body/type scale, Space Grotesk for the mark or rare display
  moments, and JetBrains Mono for compact status labels. Ship only the font
  weights used.
- Preserve Klipa's 6/10/16 px radius scale, subtle low-alpha dividers, indigo
  focus/selection, logo fallback treatment, LIVE badge, error language, and
  brand gradient. Revalidate contrast in this repository rather than assuming a
  copied token remains accessible in a new composition.
- Use compact desktop density: channel rows target 56 px, toolbars 44–48 px,
  and panes use restrained 12/16 px spacing. Avoid enlarged mobile cards,
  floating bottom navigation, or Android-TV rails.
- The video is the dominant surface. Use flat surfaces and borders; avoid
  acrylic blur, glass effects, large shadows, animated backgrounds, and custom
  title-bar decoration in v1. The native Windows frame and caption buttons
  remain intact; supported DWM dark-mode/color hints may make it match the Klipa
  surface without reimplementing window chrome.
- Animation is limited to 120–180 ms focus/selection/pane transitions and
  respects Windows reduced-motion preferences. No decorative looping
  animation.
- System theme is the default. Both light and dark themes must pass WCAG 2.2 AA
  contrast for text and controls.
- Maintain golden screenshots at 1440×900 and 1024×768 for onboarding, library,
  playback, error, and settings. Product review compares those screens with the
  current Klipa app for brand continuity while allowing desktop-native layout.

### 6.3 Keyboard map

| Shortcut | Action |
|---|---|
| `Ctrl+O` | Open local M3U/M3U8 file |
| `Ctrl+Shift+O` | Open the add-source dialog |
| `Ctrl+F` | Focus channel search |
| `Enter` | Activate focused channel or control |
| `Space` | Play/pause when focus is not in a text field |
| `M` | Toggle mute when focus is not in a text field |
| `Up` / `Down` | Move in lists; adjust volume when the player volume control is focused |
| `Page Up` / `Page Down` | Previous/next visible channel while player has focus |
| `F` or `F11` | Enter full screen |
| `Esc` | Exit full screen, dismiss dialog, or close temporary overlay |
| `Ctrl+R` | Refresh active source after confirmation if an import is running |
| `Alt+Left` | Return focus from player/details to channel list |

All shortcuts must have discoverable menu or tooltip equivalents. Text inputs
always take precedence over single-letter shortcuts.

### 6.4 Accessibility

- All functionality must be reachable with keyboard only and have a persistent,
  high-contrast focus indicator.
- Windows Narrator shall announce controls, channel rows, favorite toggle state,
  loading progress, current playback state, and errors.
- Text and layout shall remain usable at 200% Windows text scale and at 100%,
  125%, 150%, and 200% display scaling.
- No status is communicated by color alone.
- Touch-sized mobile controls are not required, but interactive desktop targets
  shall be at least 32×32 logical pixels and comfortably spaced.
- High Contrast themes and reduced-motion preferences shall preserve full
  functionality.
- Automated semantics checks do not replace a manual Narrator and keyboard
  walkthrough before v1.

## 7. Klipa promotion and attribution

### 7.1 Promotion surfaces

The player may promote the mobile/TV app in exactly these non-blocking places:

1. A secondary **Klipa on phone and TV** link below the primary import actions
   on first run.
2. A compact footer link in the source/group rail after import.
3. The About screen, alongside equally visible privacy and license information.
4. The desktop landing page and product documentation.

The app shall not show promotional modals, timed nags, interstitials, autoplayed
media, notification ads, or repeated dismissal state. Promotion must never
interrupt import or playback.

Mobile copy should explain the incremental value rather than saying only
"download Klipa": phone/tablet use, Android TV, pairing, full EPG, reminders,
VOD/series, and multiview where those features are currently available.

### 7.2 Link behavior

- All app promotion links open only after an explicit click in the default
  browser.
- Use one stable first-party route, for example
  `https://klipa.tv/go/mobile/windows`, so the destination can change without an
  app update.
- The route may increment a daily aggregate referral counter, but shall not
  retain a request-level event, IP address, user agent, device identifier,
  fingerprint, cookie, account, or per-install token. Access logging for this
  route is disabled or redacted in line with the published Klipa policy.
- The Windows app does not send an impression, session, installation, or click
  event directly to Klipa. The explicit browser request is the only attribution
  signal.

### 7.3 Success metrics

Primary product signal:

- Monthly qualified visits to the Klipa mobile landing route originating from
  the Windows player.

Acquisition and trust signals:

- Microsoft Store acquisitions and rating.
- Desktop download counts and support issue resolution time.
- Ratio of actionable bug reports to release downloads.
- Organic backlinks and visits to `klipa.tv/windows/`.

Guardrails:

- No promotional surface may reduce first-play task completion in moderated
  testing.
- No telemetry is added merely to improve measurement.
- Referral targets are set after a 30-day baseline; the initial spec does not
  invent a conversion percentage without traffic data.

## 8. Privacy, security, and content policy

### 8.1 Data handling

| Data | Storage | Network behavior |
|---|---|---|
| M3U/Xtream credentials | Encrypted SQLite; database key sealed to the Windows user with DPAPI | Sent only to the provider selected by the user |
| Credential-bearing playlist/stream/EPG URL | Encrypted SQLite, queried only when needed | Sent only to that provider |
| Channel/library metadata | Encrypted SQLite under `%LOCALAPPDATA%\Klipa Player\` | No Klipa transmission |
| XMLTV guide data | Encrypted local bounded cache | Fetched directly from the user's provider |
| Logos | Local bounded cache | Fetched from URLs in the user's playlist/provider response |
| Favorites/settings | Local database | No Klipa transmission |
| Diagnostics | Local, bounded, redacted; off by default | Leaves the PC only when the user copies and submits it |
| Mobile referral | Not stored by the app | Explicit browser navigation to a first-party Klipa URL |

### 8.2 Security requirements

- Never store a password, authorization header, tokenized URL, or
  credential-bearing path/query in plaintext database fields, preferences,
  logs, crash text, window titles, recent-file lists, or clipboard output.
- Treat the complete URL as secret when it embeds provider credentials in path
  segments or unknown query keys; selective query redaction alone is not enough.
- Use the operating system TLS verifier. There is no "ignore certificate
  errors" setting.
- A user-entered source may target a private/LAN host after a clear per-source
  confirmation. App-managed redirects and guide destinations are revalidated;
  loopback, link-local, private, and multicast destinations remain blocked
  unless the user explicitly enables local-network access for that source.
- Require a clear warning before every remote URL, Xtream, or local-playlist
  import that the source is trusted to choose playback network destinations.
  libmpv follows HLS/DASH redirects, manifests, and segments outside the app's
  destination validator. Keep that residual risk explicit; do not claim DNS
  pinning or nested-request isolation.
- Limit playlist/XMLTV response bytes, decompressed bytes, entry count, metadata
  field lengths, redirect count, request duration, logo bytes, logo dimensions,
  and disk-cache size.
- Revalidate redirect schemes and strip sensitive headers on cross-origin
  redirects.
- Accept only documented media/network protocols. Never pass arbitrary command
  line options or playlist metadata to a shell.
- Reject XML `DOCTYPE`/external entities, DTD processing, and unbounded entity
  expansion. XMLTV gzip input has separate compressed and decompressed caps.
- Start libmpv without user/system config files, scripts, JavaScript/Lua,
  `youtube-dl`/external helpers, or arbitrary option passthrough. Enable only the
  protocol and demuxer surface required by section 5.3.
- Use parameterized SQLite statements and transactional migrations. Provider
  text is data and is never interpreted as SQL, HTML, XAML, Markdown, a file
  path, or a command.
- Escape all untrusted provider strings in UI and diagnostics.
- Store no secrets in source, fixtures, screenshots, issue templates, CI logs,
  or repository Actions secrets beyond release credentials.
- Publish `SECURITY.md` with a private vulnerability-reporting route and a
  supported-version table.
- Run dependency review and secret scanning on pull requests and before every
  release.

Default defensive limits are centralized constants with boundary tests, not a
page of advanced settings:

| Input/resource | v1 default limit |
|---|---|
| Source URL | 8 KiB; `http`/`https` only |
| Redirects | 5, with policy rechecked on every hop |
| M3U/Xtream response | 25 MiB and 100,000 live channels |
| M3U line / individual metadata field | 64 KiB / 8 KiB |
| XMLTV gzip / decompressed bytes | 32 MiB / 256 MiB |
| Retained XMLTV programmes | 500,000 and only the configured time window |
| Logo response / decoded dimensions | 2 MiB / 16 megapixels, max 4096 px per side |
| Connect / playlist total / EPG total timeout | 10 s / 60 s / 120 s |
| Sources per library | 20 |
| Local diagnostic ring | 2 MiB, redacted before insertion |

Exceeding a limit produces a specific, non-secret error and preserves the last
working snapshot. Raise a limit only from real compatibility evidence and add a
regression fixture for the case.

### 8.3 Threat model and deliberate limits

| Attack surface | Plausible attack | Required control |
|---|---|---|
| M3U/Xtream/XMLTV text | Oversized input, decompression/entity bomb, parser crash, malicious metadata | Byte/entry/string/depth limits, no DTD/entities, isolate parsing, escaped text, fuzz and adversarial fixtures |
| Hostile provider or app-managed redirect | Credential/header exfiltration, HTTPS downgrade, LAN request, endless response | Scheme/origin/IP checks on every app-managed hop, header allowlist, no TLS bypass, time/byte/redirect caps, per-source LAN capability |
| HLS/DASH nested media request | Manifest or DNS answer directs libmpv to an unintended host | Import-time trusted-source warning, top-level validation, narrow protocols and disabled scripts/helpers; provider destination trust is an explicit lightweight-v1 limitation |
| Channel media bitstream | Native decoder/libmpv/FFmpeg memory-safety bug | Current pinned native builds, narrow protocols/options, no scripts/helpers, prompt dependency updates, hardened release compiler flags |
| Channel logo | LAN GET/CSRF, image bomb, decoder bug, disk exhaustion | Private-IP policy, lazy fetch, content/byte/pixel/time caps, bounded LRU cache, current image decoders |
| Local file/activation | Path or command-line injection, unintended file read | Structured Windows activation, canonical paths, extension/content validation, never invoke a shell |
| Local data | Credential recovery from database/log/backup | DPAPI-sealed random database key, encrypted SQLite including journals, strict redaction, bounded local logs, reset/delete path |
| Build and dependencies | Compromised package, Action, native DLL, or release upload | Committed lockfile, minimal dependencies, pinned Action commit SHAs, artifact inventory, SBOM, checksums, signing and protected releases |
| Update/referral link | Untrusted code install or tracking redirect | Store-managed updates, signed artifacts, fixed HTTPS hosts, explicit click only, no arbitrary remote-configured URL |

Security scope is realistic rather than theatrical:

- DPAPI protects the random database key at rest from offline inspection and
  other Windows users; it does not protect against malware already executing as
  the same user.
- The in-process media decoder is the largest native attack surface. v1 keeps it
  current and tightly configured. A custom sandboxed player process is not built
  without evidence that its IPC and lifecycle complexity buys a necessary risk
  reduction.
- The configured provider or local playlist is trusted to select media network
  destinations, while every returned byte and metadata field remains untrusted
  input. A validating media proxy is intentionally outside v1 because its HTTP,
  range, redirect, manifest-rewrite, and lifecycle machinery would materially
  increase weight and failure surface.
- Use one audited SQLite encryption implementation with a random database key
  sealed by DPAPI. Do not invent per-field cryptography. This is simpler and
  safer than trying to classify thousands of M3U stream URLs, many of which
  embed credentials in unexpected paths or query keys.
- There is no plugin system, embedded webview, remote configuration, local HTTP
  server, custom update daemon, or scripting engine to secure.

### 8.4 Content and legal posture

- The app and store listing state: **Klipa Player contains no channels or
  subscriptions. Users must have the right to access the streams they add.**
- Do not bundle a demo playlist, public-channel directory, provider list,
  scraped logos, or links to unofficial playlists in production builds.
- Legal test streams may exist in test fixtures or developer documentation only
  when their licenses and intended test use are documented.
- Do not add DRM circumvention, geo-unblocking, credential sharing, connection
  limit bypass, stream restreaming, or recording features.
- Complete a release-time review against the current Microsoft Store policies,
  including third-party service/content terms.
- Codec patent and binary redistribution review is a release gate independent
  of the application source license.

## 9. Private repository and distribution policy

### 9.1 Repository boundary

The desktop repository remains private and independent. Do not publish it, its
history, or material from sibling Klipa repositories without explicit owner
approval and a fresh legal and secret review.

Allowed to move between private repositories after review:

- Playlist parsing algorithms and their synthetic tests.
- Input normalization and credential-redaction helpers.
- Domain models needed by the Windows scope.
- The playback port abstraction and Windows-safe media-engine integration.
- Selected generic design tokens and original brand assets approved for the
  desktop product.

Requires rewrite or Windows-specific replacement:

- App shell, navigation, breakpoints, input profile, onboarding, settings, and
  player controls.
- Credential persistence and library schema.
- EPG retrieval/parsing, which must be fully local.
- File activation, drag-and-drop, window management, shortcuts, packaging, and
  Windows diagnostics.
- Any mobile-oriented service initialization.

Never move:

- `.git` history, private branches, internal instruction files, deployment
  documentation, server addresses, credentials, private URLs, environment
  files, or local logs.
- `infra/`, mobile store automation, marketing working files, Android/iOS
  projects, signing material, backend pairing code, or production configuration.
- Generated files that embed absolute paths or machine/user information.

Every moved file receives a manual review plus an automated secret scan before
its first commit in the destination repository.

### 9.2 License and trademark

- First-party application source remains private and is not authorized for
  redistribution. Its final external license is an owner/legal decision.
- Third-party code and binaries retain their own licenses and appear in
  `THIRD_PARTY_NOTICES.md` and the in-app Licenses screen.
- The Klipa name and logo require separate approval; `TRADEMARKS.md` records the
  provisional policy for future review.
- External binary distribution requires a complete corresponding internal
  build record, notices, SBOM, checksums, and all license obligations to be met.

This section is a product decision, not legal advice. Resolve any ownership,
codec, trademark, or distribution uncertainty before publication.

### 9.3 Repository baseline

The private repository includes:

- `README.md` with product boundary, screenshots, no-content disclaimer, build
  instructions, privacy summary, mobile link, and roadmap.
- `LICENSE`, `NOTICE`, `TRADEMARKS.md`, `THIRD_PARTY_NOTICES.md`,
  `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, and `SUPPORT.md`.
- Issue forms for bug, provider compatibility (with explicit secret warnings),
  and feature requests.
- Pull-request template with tests, screenshots for UI changes, license
  confirmation, and DCO checklist.
- Protected `main`, required CI, dependency updates, release notes, semantic
  versioning, and a documented support window.

## 10. Technical architecture

### 10.1 Technology decision

Use current **stable Flutter** for the Windows UI and current stable modular
`media_kit` packages for libmpv-backed playback. Pin exact versions in the
repository and CI; do not build production on Flutter beta/master, Windows App
SDK preview, Git dependencies, or floating native DLL downloads.

This is the smallest low-risk path because it keeps parsing, state, UI, and
tests in Dart; has a maintained Windows video renderer; renders Klipa's custom
visual language without a browser; and avoids writing a native video surface
bridge as part of the product. It is not permission to bring the private mobile
app's entire dependency graph.

The deliberately small stack is:

- Flutter/Dart, exact stable SDK pinned.
- `flutter_riverpod` for application state and dependency boundaries. Use only
  stable APIs; no experimental persistence or mutation layer.
- `media_kit`, `media_kit_video`, and the unified current
  `media_kit_libs_video` native package, subject to the Phase 0 binary and
  license audit.
- Direct `sqlite3` FFI bindings with one audited SQLCipher or
  SQLite3MultipleCiphers build for indexed channel/EPG data, parameterized SQL,
  transactions, and explicit migrations. A random database key is sealed with
  per-user DPAPI. Do not add custom field crypto or an ORM/code-generation layer
  unless direct SQLite is proven to be a maintenance problem.
- `dart:io` `HttpClient` behind one small hardened client for playlist, Xtream,
  EPG, and logo requests. Do not add multiple HTTP frameworks.
- A streaming XML event parser with DTD/external entities disabled.
- A small reviewed Windows FFI/runner layer for per-user DPAPI, file activation,
  drag-and-drop, window bounds/full screen, and opening approved external URLs.

Runtime direct dependencies are capped at **12 packages**, excluding Flutter
SDK packages and first-party local packages. Each dependency needs a one-line
reason, active-maintenance check, license, native-binary inventory, and removal
test in `docs/dependencies.md`. The lockfile is committed. Temporary dependency
overrides need an issue, owner, and removal release.

Do not add Electron, Tauri, a WebView, React, a local web server, `go_router`, a
second state framework, a service locator, model-generation framework, general
plugin system, or background-job framework in v1. The app has one window and a
small navigation surface; those layers solve problems it does not have.

| Option | Decision | Reason |
|---|---|---|
| Flutter + modular media_kit | **Use** | Current Windows support, no webview, existing Dart knowledge, branded UI, least custom media integration |
| WinUI 3 + C# | Fallback only if Flutter misses Phase 0 budgets | Modern native Windows UI, but requires a new libmpv rendering bridge and full domain rewrite |
| Tauri/Electron/web UI | Reject | WebView/browser boundary adds attack surface and libmpv embedding complexity; browser media does not meet IPTV protocol/codec needs |
| Custom Rust/Slint/iced UI | Reject for v1 | Attractive footprint, but custom video texture, accessibility, packaging, and contributor tooling create more product than player |
| Qt/QML + libmpv | Reject for v1 | Mature but adds a second complex native stack, deployment/licensing work, and little reusable Klipa code |

The media dependency is not irrevocable. `VideoPlayerPort` remains the boundary
so a direct libmpv or other backend can replace `media_kit` without rewriting
the library and UI layers. That interface is the abstraction; do not create a
generic media framework around it.

### 10.2 Simplicity rules

- One process, one window, one encrypted database, one state framework, one
  hardened HTTP client, and one media player instance.
- Use the shallow path **widget/view → Riverpod controller → concrete
  repository/service**. Add a domain function only for logic that is reused or
  independently testable.
- Do not create generic base repositories, an event bus, CQRS, a service
  locator, a use-case class per action, DTO/domain copies of identical data, or
  a package per feature.
- Use `Isolate.run` for bounded parse/import jobs. Do not build a worker pool,
  task scheduler, or background daemon.
- Prefer Flutter/Windows platform primitives. Add a maintained single-purpose
  package when it removes meaningful native code and passes the dependency
  policy; do not rewrite a secure native dialog or drop target merely to avoid
  one small dependency.
- Optimize measured bottlenecks. Virtualized lists, indexed SQLite queries, lazy
  logos, and one player are required; speculative caches and generalized
  extension points are not.
- Keep files cohesive and interfaces narrow, but do not split code solely to
  satisfy an architecture diagram.

### 10.3 High-level components

```text
Windows shell / activation / credentials
                  |
Desktop Flutter UI and keyboard/focus layer
                  |
Riverpod application controllers
        |                   |                    |
 Source/import core     Local EPG core      Playback port
        |                   |                    |
 Encrypted SQLite      XMLTV cache          media_kit/libmpv
        |                   |                    |
 DPAPI-sealed DB key   Hardened HttpClient  Provider stream
```

Rules:

- UI depends on application interfaces, not directly on native plugins.
- Provider HTTP, logo HTTP, and playback HTTP share redaction rules but use
  separate clients and byte/time limits.
- Secret retrieval is explicit and short-lived. Domain objects expose opaque
  secret references rather than passwords or credential-bearing URLs.
- Parsing runs outside the UI isolate once input exceeds a small threshold.
- A source refresh commits database changes transactionally after successful
  parse; it never clears a working library first.

### 10.4 Proposed repository layout

```text
klipa-desktop/
  .github/
    ISSUE_TEMPLATE/
    workflows/
  assets/
    branding/
    fonts/
  lib/
    app/
    core/
      diagnostics/
      localization/
      network/
      security/
    data/
      database/
      credentials/
      models/
    features/
      onboarding/
      sources/
      library/
      epg/
      player/
      settings/
      about/
    platform/
      windows/
    widgets/
  test/
    fixtures/
    unit/
    widget/
  integration_test/
  windows/
  tool/
  LICENSE
  NOTICE
  TRADEMARKS.md
  THIRD_PARTY_NOTICES.md
  README.md
  pubspec.yaml
```

### 10.5 Platform profile

Do not reuse the mobile app's touch-versus-TV binary profile unchanged. Define
Windows explicitly:

- `PlatformClass.windowsDesktop`
- `InputMode.mouseKeyboard`
- `SurfaceDensity.desktopCompact`
- `ChromeMode.windowed`

Layout and behavior use both platform and viewport constraints. Window width
may collapse panes but cannot change the input model to TV remote or mobile
touch.

### 10.6 Data model

Minimum persisted entities:

- `PlaylistSource`: ID, kind, display name, non-secret metadata, secret
  reference, import/refresh timestamps, status, EPG secret reference.
- `Channel`: stable ID, source ID, provider ID/tvg ID, name, group, number,
  logo URL, stream secret/reference, non-secret playback metadata.
- `Favorite`: stable channel identity plus source identity.
- `Programme`: channel/tvg ID, title, start/end, optional description, EPG
  snapshot ID.
- `AppSettings`: locale, theme, playback profile, fit, window state, last
  selected source/group/channel, cache limits.
- `SchemaMetadata`: schema version and migration status.

The database and its journals are encrypted with a random key sealed to the
current Windows user through DPAPI; its directory also receives user-only
filesystem ACLs. Store stream URLs/headers in a table not selected by channel
list queries, and retrieve them only for import, refresh, EPG, or playback. Do
not cache plaintext secrets in global state, diagnostics, provider objects, or
widget models, and overwrite temporary byte buffers where the platform API
permits.

### 10.7 Network behavior

- No network request on a clean first launch.
- Import contacts only the user-entered provider and policy-valid redirects.
  Playback may additionally contact media hosts selected by a trusted HLS/DASH
  source; these libmpv requests are outside the app-managed validator.
- EPG contacts only the configured provider URL and policy-valid redirects.
- Logos load only when their rows become visible and respect cache/network
  limits.
- Klipa is contacted only after the user activates a Klipa link or manually
  requests an update check from About.
- There is no periodic analytics, remote config, news, ad, or heartbeat
  request.

## 11. Lightweight budgets

"Lightweight" is enforced as behavior and budgets, not claimed because the UI
looks simple. Phase 0 records a reference PC and adjusts a budget only with a
written reason.

| Dimension | v1 budget |
|---|---|
| Compressed x64 ZIP/MSIX payload | Target ≤ 80 MB; hard review at 100 MB |
| Installed application, excluding user cache | Target ≤ 200 MB |
| Cold start to interactive shell on reference SSD | p50 ≤ 2 s, p95 ≤ 4 s |
| Idle memory after library load, no player | Target ≤ 150 MB; hard review at 180 MB |
| 1080p single-stream memory | Target ≤ 350 MB; hard review at 450 MB, excluding driver-reserved GPU memory |
| Idle CPU after settling | < 1% of one logical CPU on reference PC |
| Search/filter response at 50,000 channels | p95 ≤ 100 ms |
| Parse/save local 10,000-channel fixture | ≤ 3 s on reference PC |
| UI dispatch overhead before player open | ≤ 100 ms |
| First frame for local-network fixture | p50 ≤ 2 s, p95 ≤ 4 s |
| Default logo cache | ≤ 200 MB with LRU eviction |
| Background processes/services | 0 |
| Native player instances | 1 maximum |
| Direct runtime package dependencies | Target ≤ 14; every package justified |

Provider latency is reported separately from app overhead. A slow or failing
internet provider must not be represented as an app-performance regression.

## 12. Build, CI, and release

### 12.1 Pull-request CI

Required checks:

- Dart formatting.
- Flutter analysis with warnings and infos treated as failures.
- Unit and widget tests on every pull request.
- Windows x64 release build on every pull request or protected merge queue.
- License/dependency review, OSV/native CVE review, and secret scan.
- Parser adversarial corpus covering oversized, malformed, entity, encoding,
  redirect, header-injection, and redaction cases.
- Generated localization/schema files checked for drift.
- A release-bundle inventory that fails on unapproved binaries or missing
  notices.
- GitHub Actions pinned to reviewed commit SHAs with least-privilege permissions;
  pull-request jobs do not receive release secrets.
- Release runner and native binaries checked for supported MSVC hardening such
  as ASLR, DEP, and Control Flow Guard. A missing flag is documented or blocks
  release according to the Phase 0 threat review.

### 12.2 Release pipeline

For a protected version tag:

1. Check out the exact tag in a clean Windows runner.
2. Restore the pinned Flutter/toolchain and locked dependencies.
3. Run all CI plus Windows integration smoke tests.
4. Build release x64 binaries, the per-user Windows setup/portable archive,
   and the Debian/Ubuntu package. MSIX is a later Store-specific option.
5. Generate `THIRD_PARTY_NOTICES`, SBOM, SHA-256 checksums, and build provenance.
6. Sign artifacts when an approved production signing route exists.
7. Stage artifacts privately for manual verification; publishing requires a
   separate explicit approval.
8. Test clean install, upgrade from the previous supported version, playback,
   and uninstall on clean Windows 10/11 and supported Debian/Ubuntu VMs.
9. Publish only the approved signed artifacts. A Microsoft Store submission is
   optional after a Store identity and MSIX workflow exist.

Never publish a production MSIX signed only with a self-signed test
certificate. Microsoft Store distribution is preferred for mainstream users
because Store MSIX provides trusted signing and managed updates. If direct
GitHub binaries are unsigned, label them for technical users and document the
expected Windows warning; obtain production signing before presenting direct
download as the default path.

### 12.3 Distribution order

1. Private/local developer builds.
2. Privately shared signed release candidates for technical testers.
3. Approved private or first-party website downloads with Windows setup/ZIP,
   Linux package, checksums, SBOM, and notices.
4. Optional Microsoft Store stable MSIX after a Store identity exists.
5. WinGet/APT manifests only after stable signed packages and repository
   identities exist.

The app must not implement its own privileged updater service.

## 13. Test strategy

### 13.1 Automated coverage

- M3U parsing variants, malformed lines, encodings, metadata, header directives,
  duplicate channels, and large fixtures.
- Xtream input normalization, live-only endpoint use, authentication states,
  expiry, redirects, transport failures, and M3U fallback behavior where
  retained.
- Credential classification and redaction for query, path, headers, exceptions,
  and diagnostics.
- Atomic refresh, stable channel identity, favorite preservation, schema
  migration, and recovery from interrupted writes.
- XMLTV/gzip limits, time zones, exact ID matching, stale cache, and partial
  provider failures.
- Player-controller lifecycle, retry policy, error mapping, volume, and
  channel-change races using a fake playback port.
- Keyboard traversal, shortcuts, text-field precedence, Narrator semantics, and
  pane collapse at supported sizes.
- Promotion links require explicit activation and use only the approved URL.
- Network policy test proving there is no Klipa request during first launch,
  import, refresh, browsing, EPG, or playback.

### 13.2 Manual Windows matrix

Minimum v1 validation:

- Windows 11 current stable: Intel integrated GPU, AMD integrated/discrete GPU,
  and NVIDIA GPU.
- Windows 10 22H2 x64 on at least one supported GPU.
- 100%, 125%, 150%, and 200% display scaling.
- Light, dark, and High Contrast themes.
- Single and multiple monitors; move the playing window between different DPI
  displays.
- Windowed, maximized, full screen, minimize/restore, sleep/resume, and display
  disconnect.
- Keyboard-only and Windows Narrator walkthrough.
- Clean standard-user account without administrator rights.
- Clean install, upgrade, uninstall, and reinstall.

### 13.3 Test content

- Keep small synthetic M3U and XMLTV fixtures in the repository.
- Network playback tests use legally documented public test streams intended
  for interoperability testing, never personal subscriptions.
- Secrets and real provider endpoints are forbidden in fixtures, screenshots,
  CI variables, and bug templates.
- Provider-specific reports must include redacted diagnostics and a minimal
  synthetic reproduction where possible.

## 14. Delivery plan

### Workstream A — foundation

- Maintain the private repository and governance files.
- Pin Flutter/toolchain and establish Windows CI.
- Generate Windows runner, product identity, icons, and window lifecycle.
- Complete media, binary-license, and secret-extraction spikes.

### Workstream B — domain and persistence

- Port/rewrite safe playlist input, parser, Xtream live client, domain models,
  and redaction.
- Implement database, schema migrations, credential store, atomic refresh, and
  cache policies.

### Workstream C — desktop product

- Implement onboarding, three-pane shell, search/filter, source management,
  favorites, settings, and responsive behavior.
- Implement keyboard/focus/Narrator from the first UI increment.

### Workstream D — playback

- Implement Windows media adapter, player controller, overlay, full screen,
  error/retry states, renderer diagnostics, and teardown tests.

### Workstream E — local EPG

- Implement local XMLTV/gzip fetch, bounded streaming parser, exact matching,
  cache, now/next UI, and independent failure handling.

### Workstream F — launch and promotion

- Add restrained in-app Klipa links, Windows landing page, referral route, and
  README cross-links.
- Finish packaging, signing, Store listing, privacy/legal copy, screenshots,
  release automation, SBOM, and support runbook.

Each workstream lands in small reviewable increments. EPG and promotion do not
block early playback prototypes, but all v1 requirements block stable launch.

## 15. v1 acceptance criteria

v1 is ready only when all of the following are true:

### Product

- A standard Windows user can install, launch, import each source type, find a
  channel, play it, enter full screen, and return without documentation.
- A 50,000-channel fixture remains searchable and scrollable within budget.
- Source refresh preserves the previous snapshot on failure and favorites on
  success.
- Now/next guide data works locally and a guide outage never blocks playback.
- There are no VOD/series/multiview/recording controls or unfinished placeholders.

### Privacy and security

- Database, preferences, logs, diagnostics, and crash output contain no test
  secrets after M3U and Xtream scenarios.
- A second Windows user and an offline copy of the app-data directory cannot
  open the database with the first user's sealed key.
- Packet inspection confirms no Klipa-owned endpoint is contacted until the user
  clicks a Klipa link or requests an update check.
- TLS errors cannot be bypassed in settings.
- Import, EPG, logo, redirect, and cache limits have automated tests.
- App-managed import, EPG, and redirect requests cannot reach
  loopback/private/link-local hosts without the explicit per-source LAN
  capability; their DNS answers and every redirect hop are covered by tests.
- Every import path discloses that libmpv HLS/DASH subrequests and later DNS
  resolution are not isolated by those app-managed destination controls.
- XML entities/DTD, unapproved request headers and stream protocols, libmpv
  scripts/config/helpers, and shell execution remain disabled in the release
  bundle.
- Secret scanning, dependency review, binary inventory, license audit, SBOM, and
  third-party notices pass for the exact release artifact.

### Desktop quality

- The manual Windows/GPU/DPI matrix passes with no release-blocking rendering,
  decode, focus, or lifecycle defect.
- All actions work with keyboard only; Narrator identifies every actionable
  control and important state.
- No clipping at 200% text/display scaling or in High Contrast mode.
- Full screen restores the correct monitor and previous window bounds.
- The media engine fully tears down after repeated channel changes and app exit.

### Private source and distribution

- An authorized developer can build the tagged release from internal
  instructions on clean Windows and Linux machines.
- Repository history contains no material that belongs to another Klipa
  repository beyond intentionally reviewed and transferred source.
- License, trademark, security, support, privacy, and no-content documents are
  approved for the chosen distribution audience.
- Microsoft Store certification passes, the store package is installable without
  admin rights, and updates preserve user data.
- Distributed artifacts match published checksums and include the required
  SBOM/notices.

### Promotion

- The approved mobile link appears only in the four specified surfaces.
- Each link requires explicit activation, opens in the default browser, and is
  absent from playback overlays and error dialogs.
- Referral measurement is aggregate and consistent with the published privacy
  statement.

## 16. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Windows native media package regresses or becomes unmaintained | Build or playback failures | Phase 0 spike, pin exact artifacts, keep playback port replaceable, maintain a direct-libmpv fallback decision |
| Bundled codec/native license differs from Dart wrapper license | Distribution or legal blocker | Audit exact release binaries and build flags; ship notices/SBOM; block release on uncertainty |
| Private Klipa data crosses repository boundaries | Security and reputation damage | Allowlisted transfer, manual review, and secret scan before the first destination commit |
| Desktop scope grows into a second full Klipa app | Maintenance burden and weak mobile differentiation | Live-only v1, explicit non-goals, require a spec change for deferred features |
| Promotion makes the player feel like adware | Trust and adoption loss | Standalone value, four quiet surfaces only, no nags/telemetry, privacy information equally visible |
| Provider behavior is inconsistent and flaky | High support load | Precise errors, atomic cache, bounded retries, redacted diagnostics, documented compatibility tiers |
| Store review associates the app with unlicensed content | Launch delay or removal | No bundled content/providers, clear BYO/legal copy, current policy review, useful standalone experience |
| Windows 10 is aging while users still depend on it | Expanding compatibility cost | Windows 11 primary; Windows 10 22H2 compatibility tested and bounded; review support each major release |
| Large XMLTV or logo inputs exhaust memory/disk | Crash or denial of service | Streaming/isolate parsing, compressed/decompressed caps, decoded-image limits, bounded LRU caches |
| Credentials are embedded in unexpected URL shapes | Secret leakage | Treat unknown credential-bearing URL as wholly secret; central sanitizer; adversarial tests |
| Dependency or CI supply chain is compromised | Malicious release | Direct-dependency ceiling, lockfile, pinned Action SHAs, minimal CI permissions, native inventory, SBOM, checksums, protected signed release |

## 17. Decisions that must remain explicit

Decided:

- Separate private repository with independent history.
- Current stable Flutter desktop UI, Riverpod, modular media_kit, direct SQLite,
  a small Windows FFI layer, and a replaceable libmpv-backed playback port.
- No embedded web UI, preview framework, ORM, second state framework, plugin
  system, or background service in v1; direct runtime dependencies are capped
  at 12.
- Windows x64 first; Windows 11 plus bounded Windows 10 22H2 support.
- Live TV only through v1.
- M3U/M3U8, Xtream live, favorites, local now/next EPG.
- Local-first with no account, analytics SDK, remote crash reporter, or Klipa EPG
  service.
- Private first-party source with external licensing deferred to an explicit
  owner/legal decision, plus a separate trademark policy.
- Microsoft Store MSIX as the primary stable install path.
- Promotion is user-initiated, non-modal, and aggregate-only for attribution.

Revisit after Phase 0 evidence:

- Exact pinned Flutter/media package versions.
- Exact Windows minimum build number and whether Windows 10 remains a formal or
  best-effort target.
- Production signing route for direct GitHub binaries.
- ARM64 timing.

Required before external publication or broad distribution:

- Approved distribution destinations and whether source will remain private.
- Final Partner Center publisher identity and product-name reservation.
- Security contact address.
- Final first-party source license and trademark terms.

## 18. Primary references

- [Flutter: supported deployment platforms](https://docs.flutter.dev/reference/supported-platforms)
- [Flutter: building Windows apps](https://docs.flutter.dev/platform-integration/windows/building)
- [Flutter: architecture guide](https://docs.flutter.dev/app-architecture/guide)
- [Microsoft: choose a Windows app distribution path](https://learn.microsoft.com/windows/apps/package-and-deploy/choose-distribution-path)
- [Microsoft: sign an MSIX package](https://learn.microsoft.com/windows/msix/package/sign-msix-package-guide)
- [Microsoft: submit packages to Windows Package Manager](https://learn.microsoft.com/windows/package-manager/package/)
- [Microsoft Store policies](https://learn.microsoft.com/windows/apps/publish/store-policies)
- [media_kit repository](https://github.com/media-kit/media-kit)
- [media_kit package documentation](https://pub.dev/packages/media_kit)
- [media_kit unified native video package](https://pub.dev/packages/media_kit_libs_video)
- [Riverpod package](https://pub.dev/packages/flutter_riverpod)
- [SQLite Dart FFI package](https://pub.dev/packages/sqlite3)
- [mpv repository and licenses](https://github.com/mpv-player/mpv)

These links are implementation inputs, not permanent facts. Recheck platform,
packaging, Store, dependency, and license guidance against the versions used by
each release.
