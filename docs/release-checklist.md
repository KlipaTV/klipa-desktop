# External distribution release checklist

This checklist does not authorize publishing. Every artifact remains local
until the owner explicitly approves a release destination and audience.

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

- Windows code-signing certificate installed in the current-user certificate
  store, its thumbprint, and an approved HTTPS RFC 3161 timestamp URL.
- Optional Linux signing-key fingerprint and, if using APT, a separately signed
  repository-metadata workflow.
- `hello@klipa.tv` is the monitored private security and package contact.
- Final first-party source-license posture and Klipa trademark approval.
- Explicit approval before configuring a remote, pushing, uploading artifacts,
  opening a public repository, or creating store/repository listings.

## Windows media runtime gate

- Build `libmpv-2.dll` with `tool/build_windows_media.sh --archive-source`.
- Confirm mpv GPL mode is disabled; FFmpeg is LGPLv3-compatible; GPL, nonfree,
  Vulkan, and unused scripting/plugin branches are absent from the profile.
- Verify the staged SHA-256 files, PE import inventory, source revisions,
  licenses, toolchain versions, and corresponding-source archive.
- Build and test the release bundle through `tool/build_windows.ps1`; it must
  reject a missing or hash-mismatched vetted runtime.
- Preserve the source archive with the signed installer and portable ZIP.
