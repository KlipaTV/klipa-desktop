# External distribution release checklist

Nothing in this checklist authorizes publishing. Apart from the single Linux
release recorded below, every artifact remains local until the owner explicitly
approves a release destination and audience.

## Status update — 2026-09-12

Verified on a Linux host against `origin/main` and against the live production
download; a passing local build is not a release approval.

- One release has been cut. Tag `v0.1.1` exists on `origin` (annotated tag
  object `0e90a324a5d5edcf6c96c1b69131ad30ed155bff`) and resolves to commit
  `491d3f9c0a39ce0ba0be3f12f34c294847734f78`, which is the current `main` HEAD
  and `origin/main`. The GitHub release "Klipa Player 0.1.1 (Linux amd64)" is
  published, not a draft, and not marked pre-release. Its assets are
  `klipa-player_0.1.1-1_amd64.deb` (10,130,232 bytes), `SHA256SUMS.txt`
  (97 bytes), `sbom-source.cdx.json` (154,003 bytes), and
  `THIRD_PARTY_NOTICES.md` (2,607 bytes).
- The artifact served in production
  (`klipa.tv/downloads/desktop/klipa-player_0.1.1-1_amd64.deb`) returns HTTP 200
  and 10,130,232 bytes with SHA-256
  `d9ce557bcbc4908c858a7cfc1039aadf5d934cc4aecfee1e34333b734a9a3f51`.
- The copy published under the website's desktop download directory, the live
  production download, and the `v0.1.1` release asset are the same bytes:
  10,130,232 bytes and that same SHA-256. The `SHA256SUMS.txt` published beside
  the site artifact contains that hash and `sha256sum -c` succeeds; the
  `SHA256SUMS.txt` attached to the `v0.1.1` release carries the same line.
- Repository validation passes locally on Flutter 3.44.6 / Dart 3.12.2:
  `dart format --output=none --set-exit-if-changed lib test` (55 files,
  0 changed), `flutter analyze --fatal-infos --fatal-warnings` (No issues
  found), and `flutter test` (139 passed, 3 skipped as Windows-only).

### Traceability: partly closed by the tag, still not embedded

The released `.deb` carries no commit or revision provenance inside it.
`dpkg-deb -f` reports `Package: klipa-player`, `Version: 0.1.1-1`,
`Architecture: amd64`, a dependency list, and a description — no `Source:`, no
`Built-Using:`, and no revision field. Its control archive holds only `control`
(418 bytes): no `md5sums`, no changelog, no build metadata. The payload listing
contains no `.buildinfo`, SBOM, or revision file, and a repository-wide search
finds no occurrence of the commit SHA inside the package. The only embedded
version data is `data/flutter_assets/version.json`, which records an app name,
`version` 0.1.1, `build_number` 1, and no commit.

What moved when the release was tagged: the previous status recorded that the
served 0.1.0 artifact could not be attributed to a source revision because the
`0.1.0+1` version string was carried by 30 commits. `version: 0.1.1+1` in
`pubspec.yaml` now occurs in exactly one commit in this repository's history
(`491d3f9c0a39ce0ba0be3f12f34c294847734f78`), and tag `v0.1.1` resolves to that
same commit, so the released version string identifies a single revision and
the release record links the published SHA-256 to it.

What is still not established: that linkage rests on the tag/version convention
and on the published `SHA256SUMS.txt`, not on anything inside the `.deb`.
Nothing in the package shows which commit produced it, so a rebuild from a
different tree carrying `version: 0.1.1+1` would be indistinguishable from the
released artifact by inspection alone. The `v0.1.1` tag is an unsigned
annotated tag (`git verify-tag` reports "no signature found"), and the Linux
artifact is published unsigned, with no detached `.deb.asc`. Supply-chain
provenance therefore still depends on the release record itself; any future
release artifact must embed, or verifiably build from, the revision it claims
before its provenance can be called established.

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
