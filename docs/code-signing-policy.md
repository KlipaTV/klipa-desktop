# Code signing policy

Klipa Player desktop binaries are code-signed before any external
distribution. Signing is performed exclusively through CI-provenance flow
described below; no binary built on a personal laptop is ever signed and
shipped.

## Source of the certificate

Free code signing is provided by [SignPath.io](https://about.signpath.io),
certificate by [SignPath Foundation](https://signpath.org). The certificate is
issued to *SignPath Foundation*; Klipa Project is the published name on the
artifact metadata. SignPath Foundation is the legal publisher of record and
vouches that signed binaries were produced by an automated, verifiable build
from this repository.

## Team roles

Klipa is a solo-maintainer project. Roles are documented here so SignPath's
per-release approval workflow is unambiguous.

- **Authors / Committers** —
  [KlipaTV](https://github.com/KlipaTV).
  All direct commits to `main` are made by a maintainer.
- **Reviewers** —
  [KlipaTV](https://github.com/KlipaTV).
  Every pull request from an external contributor must be reviewed by a
  maintainer before merge. No PR may be self-merged by an external
  contributor.
- **Approvers** —
  [KlipaTV](https://github.com/KlipaTV).
  Every SignPath signing request must be manually approved in the SignPath
  web UI by a maintainer before the certificate is unlocked. No automatic
  signing is enabled.

Each role is held by the maintainer team until a second team member is added.
At that point this section will be updated to name them and the three-role
separation will become real.

## Build provenance

SignPath only signs artifacts that its origin-verification step can tie to a
commit in this repository. Signing flow:

1. A maintainer pushes a tag matching `v*` to `main`.
2. The `windows-release.yml` GitHub Actions workflow runs on `windows-latest`:
   - runs `tool/build_windows.ps1 -Configuration release` (analyze, build,
     test),
   - submits the unsigned `klipa_player.exe` to SignPath with the
     `windows-appfiles` artifact configuration and restores the signed
     executable into the release bundle,
   - runs `tool/package_windows.ps1 -SkipBuild` to assemble the installer and
     portable ZIP from the signed bundle (no Authenticode signing happens on
     the runner itself),
   - submits the unsigned installer to SignPath with the `windows-installer`
     artifact configuration.
3. The maintainer approves each request in the SignPath web UI.
4. The workflow regenerates `SHA256SUMS.txt` over the signed artifacts and
   attaches them, together with `THIRD_PARTY_NOTICES.md`, to the GitHub
   Release for the triggering tag.

The Windows media runtime (libmpv/FFmpeg, `libmpv-2.dll`) is Klipa's own
source-built, LGPL-profile binary produced by `tool/build_windows_media.sh`
from pinned upstream revisions (patch and provenance under
`third_party/windows-media`). Release builds verify its SHA-256 and refuse to
package the DLL downloaded by the `media_kit_libs_windows_video` pub package;
the verification steps live in the media runtime gate of
`docs/release-checklist.md`; see also `docs/supply-chain.md`.

## Privacy

This program will not transfer any information to other networked systems
unless specifically requested by the user or the person installing or
operating it. Klipa Player makes no Klipa service request at install or
startup. The only network access the application initiates is to a media
source the user explicitly adds, its provider-hosted guide/artwork/media, or a
future explicit external-browser promotion action. See
`docs/security-model.md` for the complete network-egress policy.

## Revocation and incident response

If a signed release is found to violate the SignPath Foundation Code of
Conduct (malware, PUA, privacy regression, or build provenance break), the
maintainer will:

- request immediate certificate revocation via `support@signpath.io`,
- yank the affected GitHub Release and its assets,
- publish a root-cause report as a GitHub Security Advisory, and
- assist SignPath Foundation with any verification.

## Contact

- Security and signing incidents: `hello@klipa.tv`.
- General issues: GitHub Issues on this repository.