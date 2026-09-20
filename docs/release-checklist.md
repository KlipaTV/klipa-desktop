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

Engineering-gated. Measured on 2026-09-20, "need hardware not available on the
current development host" was the wrong description of most of this list:

- Corrupt-media and repeated channel-switch coverage across the documented
  Intel/AMD/NVIDIA matrix, including HLS and MPEG-TS. Re-measured: an Intel GPU
  is present and usable; an NVIDIA GPU is present but unusable because
  `nvidia-smi` fails with a driver/library version mismatch, so the NVIDIA leg
  cannot be run here today; no AMD device is present. The NVIDIA leg is blocked
  by a driver problem and the AMD leg by the absence of the device, while the
  Intel leg is not hardware-blocked at all. What is still missing across the
  whole matrix is the media corpus and the per-vendor coverage.
- No Windows host or VM is available here, so install, upgrade and zero-network
  clean-launch validation on Windows 10/11 has not been run. The only Windows
  coverage in this repository is CI (`.github/workflows/ci.yml` builds the
  Windows release bundle on `windows-latest`, and `windows-release.yml`), and a
  CI build is not an install onto a clean Windows machine.
- The container engine of `tool/validate_linux_install.sh` cannot run here: the
  Docker client is installed but the daemon socket is permission-denied for the
  user running the check, so the tool refuses that engine and exits non-zero
  instead of skipping it. The Debian/Ubuntu legs are covered by the same tool's
  `rootfs` engine, measured in the 2026-09-20 status update below.
- The old "install and upgrade validation on clean Debian/Ubuntu VMs" item is
  partly answered by that same run, which measures the package against four
  supported releases. It is not a VM install, and a VM run has not been done.

## Status update — 2026-09-16: the Linux packager is deterministic and self-attributing

Verified on 2026-09-16 on a Linux host (`dpkg-deb` 1.23.7, `zstd` 1.5.7, 16
processors) against the tree carrying this section, reusing the existing
`build/linux/x64/release/bundle`. This closes the engineering half of the
attribution gap for future artifacts. It does not change the published release,
and it does not make the published bytes reproducible; see the warning below.

### Triage: the two 0.1.1 artifacts differ in packaging, not in payload

The local `dist/linux/klipa-player_0.1.1-1_amd64.deb` (10,132,352 bytes) and the
published/served artifact (10,130,232 bytes, SHA-256
`d9ce557bcbc4908c858a7cfc1039aadf5d934cc4aecfee1e34333b734a9a3f51`) were
compared by unpacking both (`ar x`, decompress the member tars) and hashing every
entry: paths, modes, sizes, symlink targets, and per-file SHA-256 are **identical**
in both, and in two fresh repackages of the on-disk bundle. The 2,120-byte gap is
therefore packaging non-determinism, not a rebuild of the application bundle.

Two consecutive runs of the previous packager over that one bundle produced
different artifacts — 10,130,270 bytes
(`9bf15300870e5e8a5b7c173ff3257d33ceedeae97d8d27fe36ea1e2eee920d3c`) and
10,130,128 bytes
(`284b80d79d3560f219f6be096bd13f0f362db8efef00d7d79368edba3e7ae0bc`) — the
first difference at byte 33, inside the mtime field of the first ar member
header. The payload was unchanged between them.

### What changed

`tool/package_linux.sh` now pins `SOURCE_DATE_EPOCH` (derived from the commit,
integer-validated, with an explicit override for tagged rebuilds), normalises
every staging mtime to that epoch as its last write before packaging, and pins
the compressor to `--uniform-compression -Z zstd -z 19 --threads-max=1`. Two
consecutive runs over the same commit and bundle now yield one hash
(`d4f73f39b9450020749468918338e1b7fb9d3f25e0ae1a90d15a6ef0a1ae08d2`), `cmp`
reports no difference, and all 53 `data.tar` plus 2 `control.tar` entries carry
a single mtime equal to the epoch. The recipe and the empirically determined
zstd default are recorded in `docs/packaging.md`.

The package also identifies its source revision: `Source-Revision` in the
`control` member and `/usr/share/doc/klipa-player/SOURCE_REVISION` in the
payload.

This establishes **packaging** determinism, not build determinism: both runs
reused an existing Flutter release bundle. Reproducing a `.deb` from source still
requires reproducing the Flutter/Dart build that produces that bundle.

### The published `v0.1.1` artifact is not reproducible and must not be republished

The published artifact was built by the previous packager. Its bytes are
unchanged and remain the released artifact; the checksum recorded above stays
the authority for it. A rebuild of `v0.1.1` with the current packager will
**not** reproduce `d9ce557b…`: the package carries an additional payload file and
control field, its member mtimes are the commit's timestamp rather than the wall
clock, and its compressor flags are now explicit. No release should be re-cut or
re-uploaded on the expectation that the published hash can be regenerated.

A fixed compressor level and thread count remove build-host variation. They do
not remove toolchain-version variation: a different `libzstd` or `dpkg` produces
a different, self-consistent stream. Published checksums should therefore be
recorded together with the packaging toolchain that produced them.

## Status update — 2026-09-20: the Linux .deb measured on clean Debian and Ubuntu systems

Verified on 2026-09-20 on a Linux development host (`dpkg` 1.23.7,
`bubblewrap` 0.11.1), from two complete runs of
`tool/validate_linux_install.sh` against commit
`374f7e3bccdba15d9bf6fbc9f23b94bb79b8f867` (`origin/main`). Nothing was
published, tagged, signed or uploaded, and this section changes no artifact: the
published `v0.1.1` bytes stay exactly as published.

The tool builds a clean base system for each release out of *that release's own
archive*: it resolves the package's dependency closure with `apt-get` against an
empty dpkg status, adds the release's Essential packages (apt omits those by
design, because it assumes a running system already has them), extracts the
closure into a private root filesystem, configures it with that release's own
dpkg running inside the root under `bubblewrap`, then installs the `.deb` under
test, inspects the installed layout, embedded provenance and dynamic links,
executes the binary under Xvfb inside the root, removes it again, and exercises
the upgrade path. It also verifies after each leg that the host's own dpkg and
loader state was unchanged. It is not a virtual machine: it is the same package
set a clean system of that release would have. It can therefore say nothing
about real hardware, a real kernel configuration or a real display.

Package under test: `klipa-player` 0.1.1-1, 10,132,798 bytes, SHA-256
`8432837a08372a88ba5f955ba79988c5a025fa36020b31fbb77c0f2f5f59f05d`.

### Result per release

- **Debian 12 (bookworm, glibc 2.36)** — FAIL. The release publishes every
  declared dependency (`libgtk-3-0` 3.24.38-2~deb12u3, `libmpv2` 0.35.1-4,
  `libsecret-1-0` 0.20.5-3) and resolves a 362-package closure on a clean
  bookworm system. The package installs and reaches `install ok installed`; all
  53 owned paths are present, of which 28 are files; the embedded
  `Source-Revision` names this commit; removal leaves no packaged file behind (28
  files removed, 8 owned directories retained, as dpkg intends); and the upgrade
  path `0.1.1-0` to `0.1.1-1` moves the version while keeping an identical path
  set and byte-identical file contents. What fails is the payload itself: the
  bundled `libflutter_secure_storage_linux_plugin.so` requires `GLIBC_2.38` and
  bookworm provides 2.36, so the loader refuses to start the program there
  (`version \`GLIBC_2.38' not found`). No other ELF object in the package needs
  more than `GLIBC_2.34`.
- **Debian 13 (trixie, glibc 2.41)** — PASS. `libgtk-3-0` is published as
  `libgtk-3-0t64` 3.24.49-3, which the declared alternative covers, alongside
  `libmpv2` 0.40.0-3+deb13u1 and `libsecret-1-0` 0.21.7-1; the closure is 349
  packages and 348 reach `install ok installed`. Every NEEDED library resolves,
  the binary starts under Xvfb inside the clean root and is still running when
  the check's timeout fires, and removal and the upgrade transition both pass.
- **Ubuntu 22.04 (jammy, glibc 2.35)** — UNSUPPORTED, and not by the package's
  contents. jammy publishes `libgtk-3-0` 3.24.33-1ubuntu1 and `libsecret-1-0`
  0.20.5-2 in `main universe`, but **no `libmpv2`**; it ships `libmpv1`, so the
  declared `Depends` cannot be satisfied on that release at all. This is a
  distribution-support limit of the package's metadata.
- **Ubuntu 24.04 (noble, glibc 2.39)** — PASS, on the same basis as Debian 13:
  `libgtk-3-0` is published as `libgtk-3-0t64` 3.24.41-4ubuntu1, with `libmpv2`
  0.37.0-1ubuntu4 and `libsecret-1-0` 0.21.4-1build3. The closure is 357 packages
  and 356 reach `install ok installed`; every NEEDED library resolves, the binary
  starts and stays running, and removal and the upgrade transition pass.

Both runs produced this same verdict for every release, with process exit status
1: Debian 12 FAIL, Debian 13 PASS, Ubuntu 22.04 UNSUPPORTED, Ubuntu 24.04 PASS.
Each run rebuilt every root filesystem from empty (the downloaded archives are
cached between runs; nothing about the base systems is), and each verified that
the host's dpkg and loader state was unchanged.

### Defect recorded, not fixed here: this artifact needs glibc 2.38, and nothing says so

`klipa-player` 0.1.1-1 declares `Depends: libgtk-3-0 | libgtk-3-0t64, libmpv2,
libsecret-1-0`. No Debian control field can express a minimum glibc version, and
this package needs one, because one bundled plugin is built against `GLIBC_2.38`.
The measured consequences on this tree:

- On Debian 12 the package installs cleanly, every declared dependency is
  satisfied, the upgrade path works — and the program will not start.
- On Ubuntu 22.04 the declared `Depends` cannot be satisfied, so the glibc
  question does not even arise.
- Debian 13 and Ubuntu 24.04 both pass every check.

So the practical floor for this artifact is glibc 2.38, which is one supported
release higher than the packaging and its "supported Debian/Ubuntu" phrasing
imply. The remedy belongs to the bundle's build environment and the package
metadata — build that plugin against an older glibc, or state the floor where a
user can see it before installing. Neither is done here.

### One observation about the declared dependency set

On a base system that satisfies the declared `Depends` and carries an X server
and a GL stack, the program aborted at startup with
`Couldn't open libGLESv2.so.2` until the release's `libgles2` was added to that
base system; with it present, the program starts and stays running. Flutter's GTK
embedder opens a GL ES library directly and none of the declared `Depends` pulls
one in. Recorded as an observation rather than a defect: a desktop installation
will normally already have one, which is why the check adds it explicitly.

### Which engine produced this, and which one could not run

These results come from the tool's `rootfs` engine. Its `docker` engine was not
exercised: the Docker client is installed on this host, but the daemon socket is
permission-denied for the user running the check, so the tool reports that engine
as unavailable and exits non-zero instead of skipping it. The `rootfs` engine
prints, with each run, the base-system properties it cannot reproduce; the group
ownership of base-system files is the material one.

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
  AMD, and NVIDIA matrix, including HLS and MPEG-TS. Not hardware-blocked on
  Intel here; blocked on NVIDIA by a driver/library version mismatch and on AMD
  by the absence of any AMD device (measured 2026-09-20). The media corpus and
  the per-vendor coverage are missing regardless.
- Validate install, upgrade and zero-network clean launch on Windows 10/11.
  There is no Windows host or VM here, and CI builds a bundle without doing it.
- Validate install and upgrade on a real supported Debian/Ubuntu VM or machine.
  The 2026-09-20 status update below measures a private root filesystem built
  from each release's own archive, which is a different check.
- Close the glibc floor recorded in the 2026-09-20 status update: the artifact
  runs on Debian 13 and Ubuntu 24.04 but not on Debian 12, and the package's
  `Depends` cannot express that requirement.

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
