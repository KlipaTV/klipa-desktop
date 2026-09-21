# Private packaging

These workflows create local release-candidate artifacts only. They do not
upload, publish, phone home, configure updates, or contact a Klipa service.

## Windows

Install Inno Setup 6, then run from PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\package_windows.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\smoke_windows_package.ps1
```

The first command performs the native release validation, includes the three
application-local Visual C++ runtime DLLs, and creates:

- `dist/windows/KlipaPlayer-Setup-x64.exe`: per-user install, no administrator
  prompt, optional desktop shortcut, English and Spanish installer UI.
- `dist/windows/KlipaPlayer-Portable-x64.zip`: extract and run without install.

The installer has no updater, scheduled task, background service, shell
extension, file association, telemetry, or network bootstrapper. Public
distribution still requires code signing. Once the certificate is present in
the current user's certificate store, create a signed executable, installer,
and uninstaller with an explicit RFC 3161 timestamp service:

```powershell
.\tool\package_windows.ps1 `
  -SigningThumbprint $env:KLIPA_SIGNING_THUMBPRINT `
  -TimestampUrl $env:KLIPA_TIMESTAMP_URL
```

The script accepts only a certificate thumbprint, never a PFX password or
private-key path, and verifies the resulting Authenticode signatures.

## Debian and Ubuntu Linux

Install the documented Flutter build prerequisites, then run:

```bash
./tool/package_linux.sh
./tool/smoke_linux_package.sh
```

This creates `dist/linux/klipa-player_<version>_amd64.deb`. Double-clicking it
opens the distribution's package installer. The package stays small by using
the distribution's GTK, libmpv, and libsecret packages rather than embedding a
second codec stack. The keyring service supplied by the desktop environment is
used only to protect the random local database key.

The build removes its temporary staging tree after a successful package, so
`dist/linux` contains only the installable artifact.

For a detached local signature, set `SIGNING_KEY` to a GPG key fingerprint.
The packager creates and verifies the adjacent `.deb.asc` without exporting or
copying private key material. A future APT repository must separately sign its
repository metadata.

The smoke scripts launch with an empty profile, assert that clean startup
opens zero TCP connections, and uninstall cleanly. The Windows smoke installs
to a temporary per-user directory; the Linux smoke performs a real
system-wide `sudo dpkg -i` into `/opt/klipa-player` and removes the package
afterwards.

## Reproducible Linux packaging

Two runs of `tool/package_linux.sh` over one commit and one release bundle now
produce a single `.deb` hash. `dpkg-deb` is not deterministic on its own, so
three things are pinned, and each of them is load-bearing:

1. **`SOURCE_DATE_EPOCH`.** It is the only time source `dpkg-deb` uses: it sets
   the mtime of every entry in `control.tar` and `data.tar` *and* the mtime in
   the ar member headers of the `.deb` itself. Left unset, `dpkg-deb` uses the
   wall clock, so two builds of one commit can never agree. The packager derives
   it from the commit under package (`git log -1 --format=%ct`) and accepts an
   explicit `SOURCE_DATE_EPOCH` override for a tagged rebuild. It must be a
   non-negative integer; anything else, including a wall-clock value, is
   rejected rather than silently accepted.
2. **Staging mtimes.** `cp -a` keeps the bundle's own mtimes and `mkdir` /
   `install` stamp the time of the run, while `dpkg-deb` only clamps mtimes
   *newer* than the epoch — older ones survive untouched, so the clamp alone is
   not enough. The packager resets the whole tree as its last write before
   packaging: `find "$stage" -depth -exec touch -h -d "@$epoch" {} +`. `-depth`
   touches a directory after its contents (touch the parent first and writing a
   child re-bumps it); `-h` covers symlinks.
3. **Compressor flags.** `--uniform-compression -Z zstd -z 19 --threads-max=1`.
   The zstd level default was established empirically rather than assumed, by
   recompressing the extracted `data.tar` with the `zstd` CLI at each level and
   matching the built member byte-for-byte:

   | level | member size |
   | ----- | ----------- |
   | 17 | 10,592,792 |
   | 18 | 10,154,660 |
   | 19 | 10,129,920 (byte-for-byte match) |
   | 20, 21, 22 | 10,129,920 |

   So `-z 19` is the level `dpkg-deb` already used and pinning it does not
   change the artifact size. `--threads-max` does change it: on one normalized
   tree, an unpinned build (the default follows the build host's processor
   count; this measurement host reports 16) produced a 10,129,920-byte `data.tar`
   member, while `--threads-max=1` produced 10,132,156 — 2,236 bytes (0.022%)
   larger, and self-consistent at every run. The pin trades that small size
   difference for removing the build host's processor count from the inputs.

A fixed level and thread count remove host-dependent variation. They do **not**
remove toolchain-version variation: a different `libzstd` or `dpkg` emits a
different, self-consistent stream. Rebuild checks must therefore record the
`dpkg` and `libzstd` versions alongside the expected hash.

### Attribution

The package now states the revision it was built from, so provenance no longer
rests on the version string and a published checksum alone:

- `Source-Revision: <full commit SHA>` in the `control` member, readable with
  `dpkg-deb -f <deb> Source-Revision`;
- `/usr/share/doc/klipa-player/SOURCE_REVISION` in the payload, carrying the
  commit, the version, and the `SOURCE_DATE_EPOCH` in force.

`SOURCE_REVISION` overrides the commit recorded in an exported tree; it must be
a full 40-character commit SHA or the packager stops.

### What the package declares, and why: the glibc floor and the GL ES provider

`packaging/linux/control.in` declares

```
Depends: libgtk-3-0 | libgtk-3-0t64, libmpv2, libsecret-1-0, libgles2, libc6 (>= 2.38)
```

The last two members are not decoration. Each one was measured, and each one
closes a way the package could install onto a base system and then fail to
start - which is what the published `v0.1.1` artifact does on Debian 12.

#### The floor is `GLIBC_2.38`, and `libc6 (>= 2.38)` is how it is stated

Read from the packaged objects themselves, not from the build host:

```bash
cd /opt/klipa-player
for f in klipa_player lib/*.so*; do
  printf '%-52s %s\n' "$f" \
    "$(objdump -T "$f" 2>/dev/null | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1)"
done
```

| packaged object | highest versioned glibc symbol it requires |
| --------------- | ------------------------------------------ |
| `lib/libflutter_secure_storage_linux_plugin.so` | **`GLIBC_2.38`** |
| `klipa_player` (executable) | `GLIBC_2.34` |
| `lib/libdartjni.so`, `lib/libsqlite3mc.so` | `GLIBC_2.34` |
| `lib/libflutter_linux_gtk.so` | `GLIBC_2.18` |
| `lib/libfile_selector_linux_plugin.so`, `lib/libmedia_kit_libs_linux_plugin.so`, `lib/libmedia_kit_video_plugin.so`, `lib/liburl_launcher_linux_plugin.so` | `GLIBC_2.2.5` |

The exact symbols are `__isoc23_strtoll` and `__isoc23_strtoull`:

```bash
objdump -T lib/libflutter_secure_storage_linux_plugin.so | grep GLIBC_2.38
# ... (GLIBC_2.38) __isoc23_strtoll
# ... (GLIBC_2.38) __isoc23_strtoull
```

One object built against `GLIBC_2.38` sets the floor for the whole package. No
other object needs more than `GLIBC_2.34`, so 2.38 is the floor and not a
rounded-up guess. `dpkg`'s own comparator puts the releases on either side of
it, with each release's published version:

| release | `libc6` | `libc6 (>= 2.38)` |
| ------- | ------- | ----------------- |
| Debian 12 bookworm | 2.36-9+deb12u14 | not satisfied |
| Debian 13 trixie | 2.41-12+deb13u4 | satisfied |
| Ubuntu 22.04 jammy | 2.35-0ubuntu3 | not satisfied |
| Ubuntu 24.04 noble | 2.39-0ubuntu8 | satisfied |

```bash
dpkg --compare-versions 2.36-9+deb12u14 ge 2.38; echo $?   # 1
dpkg --compare-versions 2.41-12+deb13u4 ge 2.38; echo $?   # 0
```

An earlier record in `docs/release-checklist.md` stated that "No Debian control
field can express a minimum glibc version". That was wrong, and the fix depends
on it being wrong: a versioned `Depends` on `libc6` is exactly that expression,
and the package manager enforces it before anything is unpacked.

The floor must follow the payload, so it is re-measured when the bundle changes:
if a future release builds `libflutter_secure_storage_linux_plugin.so` against an
older glibc, the `objdump -T` reading above drops and `libc6 (>= ...)` must be
lowered to match it. A floor left higher than the payload needs is not a defect
the check reports; it would only mean the package asks for a newer base system
than it actually requires.

#### The GL ES provider is `libgles2`

Flutter's GTK embedder opens `libGLESv2.so.2` directly as the process starts.
Measured: with an X server, `libgl1`, `libegl1` and mesa's DRI drivers present
but `libgles2` absent, the binary aborts with `Couldn't open libGLESv2.so.2`;
with `libgles2` present it starts and stays running. The declared dependencies
used to pull in no provider of that SONAME at all.

`libgles2` was chosen by testing resolution per release, not by assuming the
name exists: it is published on all four legs (bookworm 1.6.0-1, trixie
1.7.0-1+b2, jammy 1.4.0-1, noble 1.7.0-1build1), while the older alternative
name `libgles2-mesa` is published only on bookworm and jammy. Listing the
archive confirms it ships the file the loader opens, rather than trusting a
package description:

```bash
dpkg-deb -c libgles2_1.6.0-1_amd64.deb | grep libGLESv2
# /usr/lib/x86_64-linux-gnu/libGLESv2.so.2
# /usr/lib/x86_64-linux-gnu/libGLESv2.so.2.1.0
```

#### What each release's apt does with the package now

Resolution was tested against each release's own index, with a clean dpkg
status, using simulation only (`apt-get -s install`; nothing is downloaded or
installed by the test):

| release | apt result with the corrected metadata |
| ------- | -------------------------------------- |
| Debian 12 bookworm | refuses: `klipa-player : Depends: libc6 (>= 2.38) but ...`, solver reports the conflicting assignment `klipa-player:amd64 Depends libc6 (>= 2.38)`; exit 100 |
| Ubuntu 22.04 jammy | refuses: the conflicting assignment named is `libmpv2`, unchanged - jammy ships `libmpv1` |
| Debian 13 trixie | resolves: `Inst libc6 (2.41-12+deb13u4)`, `Inst libgles2 (1.7.0-1+b2)`, `Inst klipa-player (0.1.1-1 local-deb)`; exit 0 |
| Ubuntu 24.04 noble | resolves: `Inst libc6 (2.39-0ubuntu8)`, `Inst libgles2 (1.7.0-1build1)`, `Inst klipa-player (0.1.1-1 local-deb)`; exit 0 |

#### The published `v0.1.1` artifact keeps its bytes

The corrected metadata is a change to **future** packages only. The published
`v0.1.1` `.deb` (10,130,232 bytes, SHA-256
`d9ce557bcbc4908c858a7cfc1039aadf5d934cc4aecfee1e34333b734a9a3f51`) was built by
the earlier packager with the old `Depends` line, is not rebuilt, not
republished, and not re-signed; its record stays what it was. Nothing in this
document authorizes a re-upload of it. The corrected metadata lands with the
next release, whenever that is cut.

Packaging determinism is unaffected: `tool/package_linux.sh` still derives
`SOURCE_DATE_EPOCH` from the commit, normalises the staging tree and pins the
compressor, and two consecutive local builds of one commit after this change
produced one SHA-256 and `cmp` reported no difference.

#### How the class stays checkable

`tool/validate_linux_install.sh` decides two things it did not decide before,
so this defect class cannot return silently:

- The declared `Depends` are evaluated **with their version constraints**
  against the release's own index (`dpkg --compare-versions`, each release's
  published version). A release that publishes the name but not a satisfying
  version is reported as `METADATA-UNSUPPORTED`: the package's own metadata
  would refuse the install, which is neither a pass nor a defect of the
  package. A release that does not publish the name at all stays `UNSUPPORTED`.
- The closure of the package **alone** (before the leg's own X/GL runtime
  extras are added) is searched for an archive that actually ships
  `libGLESv2.so.2`. Finding none is a `FAIL`, with the abort message quoted in
  the verdict - the launch check alone cannot see this, because the extras it
  installs would supply the provider and mask the gap.

Both directions were demonstrated on a scratch copy of the tree, and the
results are recorded in `docs/release-checklist.md`.

### The published `v0.1.1` artifact does not become reproducible

The published `v0.1.1` `.deb` (10,130,232 bytes, SHA-256
`d9ce557bcbc4908c858a7cfc1039aadf5d934cc4aecfee1e34333b734a9a3f51`) was built
by the earlier packager and its bytes are unchanged; they must not be
republished. A rebuild of `v0.1.1` from the same bundle with the current
packager will therefore **not** match that hash — the package now carries an
extra file and control field, its mtimes are the commit's rather than the wall
clock's, and its compressor flags are pinned. The published checksum remains
the authority for the published artifact. Determinism applies from the first
release cut with this packager forward.
