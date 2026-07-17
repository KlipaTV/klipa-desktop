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
