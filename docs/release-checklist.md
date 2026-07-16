# Private-to-public release checklist

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

- Replace or independently rebuild and license-review the Windows libmpv DLL.
  The latest `media_kit_libs_windows_video` package currently supplies a DLL
  whose embedded version is `v0.36.0-403-g652a1dd907`.
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
- A monitored private security-reporting address to replace the placeholder in
  `SECURITY.md` and package metadata.
- Final Apache-2.0 and Klipa trademark approval.
- Explicit approval before configuring a remote, pushing, uploading artifacts,
  opening a public repository, or creating store/repository listings.
