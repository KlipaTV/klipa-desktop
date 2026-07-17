# Klipa Desktop — codebase audit (2026-07-17)

Full-repo audit of `klipa-desktop` at commit `d7b0680` (`license: relaunch as LGPL-3.0-or-later…`).
Scope: all Dart source (~6,100 LOC in `lib/`), tests, CI workflows, SignPath config, packaging, tooling, and docs.
Method: manual review of the security core (crypto, key stores, network policy, encrypted DB, HTTP client) plus three parallel deep reviews (data-ingestion layer, UI/state/playback, infra/packaging/hygiene). Every finding below was verified against the source before inclusion.

**Overall verdict:** the security architecture is unusually strong for a project this size — the weaknesses are concentrated in (a) a release pipeline that has never actually run end-to-end, (b) silent-failure paths in EPG/import handling, and (c) a handful of state-machine bugs in the UI layer.

---

## 1. Critical / High

### H1. The release pipeline cannot succeed on CI
`tool/build_windows.ps1:13` hardcodes `$env:USERPROFILE\develop\flutter\bin\flutter.bat` and throws if absent. The release workflow (`.github/workflows/windows-release.yml:88,106-108`) installs Flutter via `subosito/flutter-action` (tool-cache + PATH) and then calls this script, so every tag push / dispatch fails at "Build Windows release bundle". The repo has zero git tags — consistent with the signing/release pipeline never having been exercised. The robocopy "NTFS mirror" pattern is a local WSL workaround leaking into CI.

### H2. The "vetted libmpv" supply-chain control is dead code
The workflow downloads `libmpv-2.dll` + `.sha256` into `dist\windows-media\current` (lines 66-85), but nothing consumes that path: `build_windows.ps1:25` **excludes `dist`** from the mirror, no build file references `windows-media`, and `tool/build_windows_media.sh` (referenced by the workflow header and `docs/code-signing-policy.md:48`) **does not exist**. A signed release would ship whatever DLL the `media_kit_libs_windows_video` pub package provides — the control described in the code-signing policy is not enforced. Even as written, the hash is verified against a `.sha256` fetched from the same release asset (no independent trust anchor).

### H3. XMLTV guides using CDATA import with zero programmes, silently
`lib/data/xmltv_parser.dart:186` handles only `XmlTextEvent`; in package:xml 7.x `XmlCDATAEvent` is a sibling class, so `<title><![CDATA[…]]></title>` content falls into `default: break`. Title stays null → `_PendingProgramme.isValid` false → every programme lands in `skippedEntries` and the guide imports empty with **no error**. CDATA-wrapped EPG text is common in the wild. Compounded by H5 (the controller swallows guide errors), the user never learns anything failed. No CDATA test exists.

### H4. Deleting a source under "All channels" leaves a dangling category filter
`library_controller.dart:294` clears the group filter only when the deleted source was the *source filter* (`clearGroup: sourceFilterWasDeleted`). With "All channels" selected and a group owned solely by the deleted source, `state.selectedGroup` survives while the dropdown items are re-derived from remaining channels → `DropdownButton` (`library_screen.dart:937-945`) violates its value-in-items contract: assertion crash in debug, ghost filter + "No matching channels" in release. The refresh path (`_publishSourceSnapshot`) recomputes `keepSelectedGroup` correctly; the delete path just misses it.

### H5. Guide failures are swallowed end-to-end
`library_controller.dart:529-531` (`_refreshGuide`) catches `on Object { return null; }` — a 404, timeout, or TLS failure on a user-supplied XMLTV URL produces "Imported N channels." and no EPG, forever, with no feedback. The descriptive `GuideDownloadException` messages built in `bounded_http_client.dart` are discarded. This turns H3 and M-group parsing strictness into invisible failures. (Also: on failed refresh, `schedules: schedules ?? state.schedules` keeps schedule entries for channels that may no longer exist.)

---

## 2. Medium — security

### MS1. DNS-rebinding TOCTOU in the private-network policy
`NetworkPolicy.classifyHost` (`lib/core/security/network_policy.dart:37-54`) resolves the host itself, then `HttpClient` re-resolves at connect time (`bounded_http_client.dart:136`). A rebinding DNS server can answer the policy lookup with a public A record and the connect lookup with a private address, bypassing the `allowsPrivateNetwork` gate (the app's only SSRF-toward-LAN defense; it is otherwise excellent — re-validated on every redirect hop, downgrade-blocked). Fix: resolve once and connect to the pinned IP (`HttpClient.connectionFactory`) or re-check the connected socket's remote address.

### MS2. Xtream server normalization does not strip query/credentials
`xtream_client.dart:111` uses `value.replace(path: '', query: null, fragment: null)` — in Dart, `null` means *keep* the component, so only the path is cleared. If the user pastes their full M3U link (`http://panel/get.php?username=alice&password=s3cr3t`) as the server address, the query survives `server.replace(pathSegments: …)` at lines 216-220 and the stale credentials are **persisted into `channel_secrets` for every channel and retransmitted on every playback request**. `_apiUri` and `source.location` (`.origin`) are unaffected. Fix: rebuild the URI from scheme/host/port, or pass `query: ''` handling the trailing-`?` case. Same misconception (harmless) at `local_epg_service.dart:98`.

### MS3. CODEOWNERS is invalid, voiding a signing-security gate
All `CODEOWNERS` entries use `@KlipaTV` — the **organization**, which GitHub does not accept as an owner (users or `@org/team` only). No path has a valid owner, so `.signpath/policies/klipa-player/release-signing.yml:30` (`require_code_owner_review: true`) is silently ineffective.

### MS4. SignPath artifact configuration is not schema-valid and signs nothing inner
`.signpath/artifact-configurations/windows-release.xml` lacks the required `xmlns`, uses nonexistent elements (`<authenticode-signing>`, text-node `<include>`, `<exclude-signing-certificates>`, `<metadata>` children) and an undeclared `${product-version}` parameter. Nothing descends into the ZIP/installer payload, so the inner `klipa_player.exe` would ship unsigned even if registration succeeded — contradicting the file's own comment.

### MS5. Release workflow: unpinned third-party actions + input interpolation
`subosito/flutter-action@v2` and `SignPath/github-action-submit-signing-request@v2` (the action holding the signing API token) are pinned by mutable tag, not SHA; `choco install innosetup -y` is unpinned. `${{ github.event.inputs.ref }}` is interpolated directly into PowerShell `run:` blocks in a job with `contents: write` + the SignPath token (dispatch requires write access, so hardening rather than an unauthenticated hole — use `env:` indirection). Also: the `workflow_dispatch` path can never publish (`$tag = 'main'` → `gh release create main --verify-tag` fails).

### MS6. LGPL / third-party compliance gaps in packaging
(a) Inno Setup installer ships no `LICENSE` or third-party notices (`packaging/windows/klipa-player.iss`); (b) the .deb has no `/usr/share/doc/klipa-player/copyright`; (c) the promised corresponding-source archive for libmpv/FFmpeg is never attached to releases; (d) `THIRD_PARTY_NOTICES.md` lists no notices. Any actual release would distribute LGPL-covered libmpv/FFmpeg without license texts or a source offer — contradicting the repo's own release checklist (which still lists this gate as open).

---

## 3. Medium — correctness / UX

### MC1. The import/reset "modal" overlay blocks nothing
`library_screen.dart:95-104` wraps the operation scrim in `IgnorePointer`, so everything beneath stays clickable. Navigation writes are not serialized against in-flight imports/resets; each store call opens the DB in its own isolate with **no `busy_timeout`** (`encrypted_library_database.dart:129-134`), so a navigation save during a large import fails with SQLITE_BUSY and surfaces as *"The encrypted library could not be opened. Reset may be required."* — a false corruption alarm. Worse: clicking a channel during reset queues a navigation save that **recreates `library.db` right after "App data was reset."**

### MC2. One throwing `Player.dispose()` poisons all future playback
`player_pane.dart:123,139,318-342`: `_openQueue` is rebased with bare `.then(...)` and dispose paths have no catch. If media_kit's `dispose()` throws once, the queue becomes a rejected future: every later channel click waits out the 20 s timer and shows "The channel did not start in time" forever; `stop()` rethrows into reset/delete flows, silently aborting them.

### MC3. Fullscreen with no channel is an exit-proof trap
All fullscreen exit bindings (F, F11, Escape) live in the `channel != null` branch (`player_pane.dart:434-456`); `_EmptyPlayer` binds none, and fullscreen hides the rail/browser (`library_screen.dart:306`). A Ctrl+R refresh that drops the playing channel strands the user in a fullscreen empty pane with no in-app exit.

### MC4. Import entry points inconsistently guarded; silent credential loss
Onboarding and expanded-rail buttons disable on `isImporting`, but Ctrl+O / Ctrl+Shift+O and all four compact-rail buttons (`library_screen.dart:551-576`, width < 1100) do not. Submitting the Xtream dialog during a slow refresh hits the `_operationInProgress` early-return in `_import` (`library_controller.dart:359`): dialog closes, nothing happens, no message, typed credentials discarded.

### MC5. `toggleFavorite` silently drops toggles on other channels
`_operationInProgress` includes `_favoriteWrites.isNotEmpty` and is checked **before** the per-identity dedup (`library_controller.dart:144-147,305-309`). Each write is slow (isolate + KDF, see P1), so starring three channels quickly lands only the first — the rest no-op without error.

### MC6. Parser strictness turns routine wild-data into total import failure
- `m3u_parser.dart:161-165`: one malformed `#EXTINF` (unterminated quote, missing comma) aborts the entire import with `PlaylistFormatException` — while bad URLs are warn-and-skip. A 50k-channel playlist with one junk record imports zero channels.
- `xmltv_parser.dart:275-277`: timestamps require exactly 14 digits + mandatory timezone; the XMLTV DTD allows truncated forms and optional zones (`stop` is also optional per spec but required here). Feeds using `20260716120000` (no zone) import an empty guide — silently (see H5).
- `bounded_http_client.dart:54-68`: the catch list misses `HttpException` (connection closed mid-body), `FormatException` (garbage `Location` header at line 156), and `CertificateException`. These escape untyped, which in `playlist_import_service.dart:234-238` **bypasses the Xtream get.php compat fallback that was designed for exactly the truncated-download case**, failing the whole import. `HttpException.toString()` also embeds the credential-bearing URI (the UI is saved by the redactor, but the typed-error contract is broken).

### MC7. Installer upgrade hygiene
`klipa-player.iss:45`: single `[Files]` entry with `ignoreversion recursesubdirs` and no `[InstallDelete]`/previous-uninstall → files removed between versions accumulate (stale plugin/DLL hazard). `SignedUninstaller=yes` is gated behind `#ifdef Signing`, which the CI path never defines → released uninstallers always unsigned. (AppId, per-user scope, `PrivilegesRequired=lowest`, `CloseApplications` are all correct.)

### MC8. Documentation contradicts the public relaunch
`SECURITY.md:3` still says "The source repository remains private" (on the file GitHub surfaces for vulnerability reports); similar staleness in `CONTRIBUTING.md`, `docs/spec.md:657`, `README.md:14` vs `:61`, `docs/release-checklist.md:40-49` (pre-SignPath flow), and `docs/code-signing-policy.md:52-54` (describes PowerShell cmdlets; the workflow uses the SignPath action).

### MC9. No CI besides the release workflow
No analyze/test job on PRs or pushes, no dependabot/renovate. The SignPath policy leans on PR review as its provenance gate, yet nothing machine-checks a PR before merge; tests only run inside the (broken, H1) release build.

---

## 4. Performance

### P1. Every store operation pays isolate spawn + DPAPI unprotect + full KDF
Each `LibraryStore` call — including a single favorite toggle or navigation save — spawns an `Isolate.run`, unprotects the key, and re-opens the database. The key is passed as `PRAGMA key = '<hex>'`, i.e. a **passphrase**, so sqlite3mc runs its KDF on every open even though the key is already a random 256-bit value. Using the raw-key pragma form would eliminate the KDF cost; a persistent DB isolate (or connection reuse with serialized access) would eliminate the rest and also fix the SQLITE_BUSY class of MC1.

### P2. Timeout abandons but does not cancel transfers
`bounded_http_client.dart:53,81`: `.timeout()` rejects the caller's future, but `client.close(force: true)` runs only when the inner future completes — a tar-pit server keeps the socket and up-to-25 MiB buffer alive long after the user saw "timed out".

### P3. Minor hot-path costs
- Stale queued channel-opens perform the up-to-8 s DNS policy lookup *before* the staleness check (`player_pane.dart:143-149`) — channel-surfing under slow DNS serializes lookups and produces a spurious "did not start in time".
- Expanded rail recomputes per-source channel counts O(sources × channels) inside `itemBuilder` on every rebuild — every search keystroke (`library_screen.dart:418-422`). Fine at 1-2k channels, measurable at the 100k cap. (Channel list itself is properly virtualized with `itemExtent`.)

---

## 5. Low

- `m3u_parser.dart:88,97` — warnings are unbounded: a 25 MiB playlist of unsupported lines generates ~3M warning strings (~15-20× amplification) copied across the isolate boundary; the UI only shows the count.
- `xmltv_parser.dart:124-127` — exceeding `programmeLimit` throws away the whole guide; M3U truncates with a warning. Inconsistent.
- `m3u_parser.dart:48-51` — Latin-1/Windows-1252 playlists mojibake silently (`allowMalformed: true`); UTF-16 input is rejected as "contains binary data".
- `m3u_parser.dart:70-73` — `#EXTVLCOPT`/`#EXTGRP` before `#EXTINF` (VLC-accepted ordering) silently dropped; Kodi pipe-suffixed URLs (`…|User-Agent=y`) import unplayable with the pipe percent-encoded.
- `xtream_client.dart:152-154` — panels returning `"auth": true` (boolean) are misreported as rejected credentials (`auth != '1'`).
- `playlist_import_service.dart:79,102` — corrupt stored location surfaces a raw redacted `FormatException` instead of a typed message.
- `encrypted_library_database.dart:804-805` — `readChannelSecret` skips the CRLF/allowlist header validation `loadChannels` enforces; `.cast<String,String>()` throws lazily on tampered data. Inconsistent defense on the playback path.
- `library_store.dart:468` — `_resetEncryptedLibrary` hardcodes `const DpapiSecretProtector()` instead of the injected protector (harmless today, latent trap).
- `library_controller.dart:248-254` — `renameSource` doesn't re-sort; `_restoreLibrary` doesn't sort at all → source ordering inconsistent within a session and across restarts.
- `player_pane.dart:424-427` — `dispose()` calls `onFullscreenChanged` → parent `setState` during element finalization (debug assertion risk; latent).
- `pubspec.yaml` floor `>=3.11.0` vs `pubspec.lock` `sdks: dart ">=3.12.0"` — a 3.11 SDK can't build from the committed lock; README says 3.11+.
- `tool/package_windows.ps1:51-56` — VC++ runtime DLLs copied from the build machine's `System32` rather than the VS redist directory.
- `docs/packaging.md:60-61` claims per-user smoke install; `tool/smoke_linux_package.sh` does system-wide `sudo dpkg -i`.
- Package name `klipa_player_windows` for a Windows+Linux product; Linux id is `tv.klipa.player` (cosmetic, baked into imports).
- `library_controller.dart:60-64` — playlist URL gets no upfront shape validation (unlike guide URL); the "Enter a valid playlist address." branch is near-dead code.
- Windows library location is `getApplicationCacheDirectory()` (`library_store.dart:364-366`). On Windows this maps to LocalAppData (correct — the DPAPI-sealed key must not roam), but "cache" semantics invite cleanup tools to delete the user's library; a Local non-cache path would express intent better.
- README/`docs/native-validation.md`/`tool/generate_release_metadata.sh` retain author-environment narrative (WSL mounts, private mirror) confusing for public contributors.

---

## 6. What's genuinely good (keep it this way)

- **Key management:** random 256-bit key from `Random.secure`, DPAPI-sealed with atomic temp-file + rename writes and buffer zeroization everywhere (including inside the DPAPI FFI on both directions); Linux uses the Secret Service keyring; missing-key-with-existing-DB fails closed with an honest message.
- **Encrypted DB:** sqlite3mc via the package:sqlite3 native-assets hook; fail-closed `PRAGMA cipher` probe; `trusted_schema=OFF`, `secure_delete=ON`, FK enforcement; fully parameterized SQL (the only interpolation is the app-generated hex key); bounded snapshots (20 sources / 100k channels / 500k programmes); migrations run in `BEGIN IMMEDIATE` transactions with status tracking.
- **SSRF defense:** loopback/RFC1918/CGN/link-local/ULA/v4-mapped-v6 coverage, re-validation on **every redirect hop**, HTTPS→HTTP downgrade block, `userInfo` URLs rejected everywhere, per-channel re-validation at playback. (MS1 is the one gap.)
- **Untrusted-content handling:** XXE double defense (pre-scan + doctype event rejection), gzip bombs bounded incrementally, header directives allowlisted to UA/Referer/Origin with CRLF rejection at parse **and** at DB re-load, all fields length-bounded consistently (8 KiB both sides), names rendered only via ellipsized `Text`.
- **Secret hygiene:** zero logging statements in `lib/`; every user-visible error passes through `SensitiveDataRedactor`; playback errors collapse to constants; mpv hardened (`ytdl=no`, `load-scripts=no`, `tls-verify=yes`); `source.location` stores only the origin.
- **Hygiene:** the personal-reference scrub was effective (repo-wide greps clean; fixtures use example.com/RFC-reserved ranges); dependencies minimal (13 direct, all pub.dev-hosted with sha256 in the lockfile, no git/path deps); native runner code is stock template plus a small well-guarded fullscreen MethodChannel; controller disposal hygiene and the player generation/ownership guards are clean and tested.

---

## 7. Test coverage gaps (highest value first)

1. **Controller EPG path: zero coverage** — the fake store doesn't implement `EpgLibraryStore`, so `_refreshGuide` short-circuits in every test (would have caught H5's swallow and exercised H3/MC6 wiring).
2. **XMLTV:** no CDATA case (H3), no timezone-less/truncated timestamps (MC6), no invalid calendar date, no oversized-field, no non-UTF-8.
3. **BoundedHttpClient:** 60 lines covering happy path + HTML rejection only — no redirect loop, no downgrade block, no private-redirect block, no mid-stream byte limit, no non-2xx, no timeout.
4. **Concurrency:** no tests for double-submitted imports, import-during-refresh, second-channel favorite while a write is gated (MC5), or navigation saves racing an import (MC1).
5. **M3U:** no malformed-EXTINF (MC6), quoted-comma attribute, `#EXTGRP`, truncation, or size-limit cases.
6. **Xtream:** no server-URL-with-query test (MS2), no `auth` boolean, no truncated-response/compat-fallback test (MC6).
7. **UI:** no `deleteSource` + "All channels" + owned-group test (H4); compact-rail (<1100 px) and Ctrl+O/Ctrl+Shift+O paths untested; no throwing-`dispose()` test (MC2); fullscreen-with-null-channel untested (MC3).
8. `lib/domain` models have no direct tests (low value; they're trivial).

---

## Status — fixes applied 2026-07-17

All findings below were addressed in a single working-tree change set (43 files, ~1820 insertions). `flutter analyze` is clean; 136 tests pass (the one failure, `native_player_smoke_test.dart`, needs `libmpv-2.dll` on PATH — it fails identically without our changes, so it is environmental, not a regression). Highlights:

- **Fixed:** H1 (Flutter resolved from PATH), H2 (dead vetted-libmpv path removed; media-runtime provenance stated honestly), H3 (CDATA), H4 (delete-source group recompute), H5 (guide errors surfaced), MS1 (DNS-rebinding connection pin), MS2 (Xtream credential strip), MS4 (two SignPath configs + inner-exe signing), MS5 (SHA-pinned actions, env-indirection, dispatch publish gate), MS6 (LICENSE/THIRD_PARTY_NOTICES shipped, .deb copyright), all MC items, P2 (timeout cancels), the redactor empty-host crash, and the Low list.
- **Corrected from the audit:** MS3 was wrong — `KlipaTV` is a GitHub **User** account, so `@KlipaTV` in CODEOWNERS is valid; only the dead `orgs/KlipaTV/people` links were fixed.
- **Deferred deliberately:** P1's raw-key pragma (`PRAGMA key='raw:…'`). It eliminates the per-open KDF but changes the derived key, so existing libraries would need a `rekey` migration + release note. Shipped the compat-safe half (`busy_timeout`); the raw-key swap belongs in its own change. `busy_timeout` also underpins the MC1 contention fix.
- **New CI:** `.github/workflows/ci.yml` runs analyze + build + test on PRs and pushes to main. `prefer_initializing_formals` was disabled in `analysis_options.yaml` (6 pre-existing intentional public-param/private-field constructors it can't accommodate) so the strict analyze gate stays green on real issues.

### Adversarial review round (GPT-5.6-sol, xhigh)

After the first pass, an external adversarial review flagged 7 issues — several were regressions introduced by the parallel fixes themselves. All were verified against the code and fixed:

1. **Critical — arbitrary-ref signing.** The release workflow's `workflow_dispatch` accepted a `ref` input, checked it out, and submitted it to SignPath, while SignPath origin-verifies the *run's* branch — a write-capable insider could sign unreviewed bytes from a run originating on `main`. Fixed: dropped the `ref` input; the workflow now builds/signs only `github.sha`, and only a pushed `v*` tag publishes.
2. **Major — favorite fan-out (regression from MC5).** Moving the dedup before the gate let N different-channel toggles spawn N concurrent isolates + KDFs. Fixed: writes serialize through `_favoriteWriteChain` (bounded to one at a time) while keeping per-identity coalescing. Test asserts `maxFavoriteInFlight == 1`.
3. **Major — DNS pin had no fallback (regression from MS1).** Pinning to `pinned.first` broke hosts whose first address is dead but another works. Fixed: `_open` now tries each classified address in turn (still no re-resolution). Test covers a dead-then-live address pair.
4. **Major — portable ZIP omitted license texts.** The installer shipped LICENSE/NOTICE/THIRD_PARTY_NOTICES but the portable ZIP did not. Fixed: the docs are added to the ZIP root and `LICENSE` is attached to releases.
5. **Minor — XMLTV truncation not surfaced.** The `truncated` flag stopped at `_refreshGuide`. Fixed: plumbed through `_GuideRefresh`; the completion notice now says the guide was loaded only in part.
6. **Minor — M3U header leak across an abandoned entry (regression from the pre-directive fix).** A second `#EXTINF` before a URL let the next channel inherit the abandoned entry's credential-bearing headers. Fixed: directives of an abandoned entry are cleared while leading directives still apply. Test added.
7. **Minor — odd-length UTF-16 silently truncated.** A stray trailing byte produced a valid-but-wrong host. Fixed: odd-length UTF-16 payloads are rejected. Test added.

The reviewer independently **confirmed the P1 raw-key deferral was correct** (passphrase-KDF and `raw:` keys are non-interoperable for sqlite3mc's default cipher; a safe switch needs a quiesced rekey migration). Final state after this round: `flutter analyze` clean, 140 tests pass (only the libmpv smoke test fails, environmentally).

## 8. Suggested fix order

1. **H1 + H2** — make the release workflow actually build (accept Flutter from PATH; either wire the vetted-libmpv restore into the build or delete the dead step and the policy claim), then cut a test tag end-to-end through SignPath (which will also surface MS3/MS4).
2. **H3 + MC6(timestamps) + H5** — CDATA event handling, lenient XMLTV timestamps, and surface guide errors as a notice; add the missing parser tests. This unbreaks EPG for real-world providers.
3. **MS2** — strip query/fragment properly in `normalizeServer` (credential persistence).
4. **H4, MC1, MC4, MC5** — UI state fixes: recompute group on delete, real modal barrier (`AbsorbPointer`/`ModalBarrier`) + serialize store writes or add `busy_timeout`, guard compact-rail/shortcut entry points, move the favorite dedup before the gate.
5. **MS1, MC2, MC3, P1** — pin resolved IPs (or re-check socket address), contain dispose errors in the open queue, bind Escape in the empty fullscreen branch, switch to raw-key pragma + persistent DB isolate.
6. **MS5, MS6, MC7, MC8, MC9** — SHA-pin actions, env-indirect inputs, ship license texts + source offer, installer `[InstallDelete]`, doc refresh, add a PR CI (analyze + test).
