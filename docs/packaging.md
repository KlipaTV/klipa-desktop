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

### Reproducible Linux packages

`tool/package_linux.sh` produces a byte-reproducible `.deb`: two packagings of
the same commit over the same release bundle yield the same SHA-256. Three
choices make that true, and all three are deliberate.

- **Packaging epoch.** `SOURCE_DATE_EPOCH` is derived from the commit timestamp
  of `HEAD` (`git log -1 --format=%ct`) so that two packagings of the same
  commit agree, and it is exported for `dpkg-deb`, which uses it for every
  archive timestamp. An explicit `SOURCE_DATE_EPOCH` in the environment
  overrides the derivation, which is what a release rebuild of a tagged commit
  should set. Nothing in the packager reads the wall clock.
- **Normalised staging tree.** `dpkg-deb` records the mtime of every staged file
  and directory, and the staging tree is rebuilt on each run (`cp -a` keeps the
  bundle's mtimes, while `mkdir` and `install` write the time of the run). The
  packager therefore resets every entry, symlinks included, to the epoch
  immediately before `dpkg-deb` reads the tree, rather than relying on
  `dpkg-deb` to clamp newer timestamps itself.
- **Pinned compression.** `-Z zstd -z 19` states the encoder and level
  explicitly instead of inheriting dpkg's default, and `--threads-max=1` fixes
  the number of encoder threads, because the multithreaded zstd encoder emits
  different bytes for different thread counts on the same input. Level 19
  matches `dpkg-deb`'s current default, so the artifact keeps its previous
  character; single-threading costs about 2 KB (0.02%) of package size.

Verify a change to the packager by running it twice over the same bundle on the
same commit and comparing the two hashes:

```bash
./tool/package_linux.sh
sha256sum dist/linux/klipa-player_*_amd64.deb
./tool/package_linux.sh
sha256sum dist/linux/klipa-player_*_amd64.deb
```

Packages built before this change are not reproducible. The `0.1.1-1` artifact
recorded before the fix, SHA-256
`d9ce557bcbc4908c858a7cfc1039aadf5d934cc4aecfee1e34333b734a9a3f51`, was built
without a packaging epoch or pinned compression, so it cannot be reproduced
from its commit; do not treat that hash as a rebuild check.

For a detached local signature, set `SIGNING_KEY` to a GPG key fingerprint.
The packager creates and verifies the adjacent `.deb.asc` without exporting or
copying private key material. A future APT repository must separately sign its
repository metadata.

The smoke scripts launch with an empty profile, assert that clean startup
opens zero TCP connections, and uninstall cleanly. The Windows smoke installs
to a temporary per-user directory; the Linux smoke performs a real
system-wide `sudo dpkg -i` into `/opt/klipa-player` and removes the package
afterwards.
