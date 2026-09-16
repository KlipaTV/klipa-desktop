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
