# External distribution release checklist

This checklist does not authorize publishing. Every artifact remains local
until the owner explicitly approves a release destination and audience.

## Status update — 2026-09-10

Verified on a Linux host against `origin/main`; a passing local build is not a
release approval.

- No release has ever been cut: `git tag` returns nothing and
  `gh release list -R KlipaTV/klipa-desktop` returns nothing.
- The single desktop artifact served from the website
  (`klipa.tv/downloads/desktop/klipa-player_0.1.0-1_amd64.deb`) matches its
  adjacent `SHA256SUMS.txt`. Both the computed hash and the published line are
  SHA-256
  `2fc76f633f34187e23794969d383e135248430e62f0294918587c7a9234e5d6c`.
- Repository validation passes locally: `dart format --output=none
  --set-exit-if-changed lib test`, `flutter analyze --fatal-infos
  --fatal-warnings` (no issues), and `flutter test` (139 passed, 3 skipped as
  Windows-only).

### Traceability gap (open)

The served `.deb` carries no commit or revision provenance. Its control field
`Version: 0.1.0-1` maps to the `0.1.0+1` version in `pubspec.yaml`, but that
version string is shared by every commit that carried it, so the artifact
cannot be attributed to a specific source revision. No tag, release note, or
embedded revision identifies the commit it was built from. Until an artifact is
built from and linked to a tagged commit, its supply-chain provenance is
unverified. Any future release artifact must be built from, and recorded as
attributable to, a tagged commit before it is published.

### Blockers

Owner-gated (no engineering action can clear these):

- Approval of the release destination and audience.
- `SIGNPATH_API_TOKEN` and `SIGNPATH_ORGANIZATION_ID` repository secrets, plus
  the maintainer's manual approval of each signing request in the SignPath web
  UI.
- Explicit approval before pushing a `v*` tag or creating a release.

Engineering-gated (need hardware not available on the current development
host):

- Corrupt-media and repeated channel-switch coverage across the documented
  Intel/AMD/NVIDIA matrix, including HLS and MPEG-TS.
- Install and upgrade validation on clean Windows 10/11 and supported
  Debian/Ubuntu VMs.

## Automated gates completed locally

- Strict Flutter analysis and complete Windows/Linux test suites.
- Native Windows and Linux x64 release builds.
- Real per-user Windows and Debian/Ubuntu install, zero-network clean launch,
  and uninstall smoke tests.
- Deterministic release executable fuzzing for 20,000 M3U/XMLTV mutations and
  1,000 Xtream payloads.
- CycloneDX inventory of 123 locked Flutter/Dart components.
- SHA-256 and version inventory for every native release file.
- Current package advisory scan with zero high or critical matches.
- Optional Authenticode and detached GPG signing paths that do not accept or
  persist private-key passwords.

Re-run these gates from the exact proposed release commit. Generated reports
and artifacts under `dist` are local and ignored by Git.

## Engineering gates still open

- Run corrupt-media and repeated channel-switch tests on the documented Intel,
  AMD, and NVIDIA matrix, including HLS and MPEG-TS.
- Validate install and upgrade on clean Windows 10/11 and supported
  Debian/Ubuntu VMs rather than only the development host.

## Accepted product security decision

- Keep HLS/DASH support and trust each user-added provider or local playlist to
  choose playback network destinations. Import UI discloses that libmpv may
  follow nested media references outside the app validator. Media and metadata
  remain untrusted input; a validating proxy/sandbox is outside lightweight v1.

## Owner-provided release inputs

- Windows release signing runs through SignPath in CI (see
  `docs/code-signing-policy.md`): the `SIGNPATH_API_TOKEN` and
  `SIGNPATH_ORGANIZATION_ID` repository secrets must be set, and every
  signing request needs the maintainer's manual approval in the SignPath
  web UI. A locally installed certificate thumbprint plus an approved HTTPS
  RFC 3161 timestamp URL remain an optional path for local, non-release
  packaging only.
- Optional Linux signing-key fingerprint and, if using APT, a separately signed
  repository-metadata workflow.
- `hello@klipa.tv` is the monitored private security and package contact.
- Final first-party source-license posture and Klipa trademark approval.
- Explicit approval before pushing a `v*` release tag, uploading artifacts
  outside the release workflow, or creating store/repository listings.

## Windows media runtime gate

- Build `libmpv-2.dll` with `tool/build_windows_media.sh --archive-source`.
- Confirm mpv GPL mode is disabled; FFmpeg is LGPLv3-compatible; GPL, nonfree,
  Vulkan, and unused scripting/plugin branches are absent from the profile.
- Verify the staged SHA-256 files, PE import inventory, source revisions,
  licenses, toolchain versions, and corresponding-source archive.
- Build and test the release bundle through `tool/build_windows.ps1`; it must
  reject a missing or hash-mismatched vetted runtime.
- Preserve the source archive with the signed installer and portable ZIP.
