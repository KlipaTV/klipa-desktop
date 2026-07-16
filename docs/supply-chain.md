# Supply-chain release evidence

Release metadata is generated locally from the exact source lockfile and native
release bundles. It is never downloaded from or uploaded to a Klipa service.

## Generate

Install Syft 1.44.0 or newer from its verified upstream release, build both
native release bundles, then run:

```bash
./tool/generate_release_metadata.sh
```

Set `WINDOWS_BUNDLE` when the native Windows mirror is not in its default
location. The command creates ignored, local-only evidence under
`dist/metadata`:

- a CycloneDX source SBOM covering the locked Dart/Flutter dependency graph;
- bundle-level CycloneDX records for both release outputs;
- SHA-256 for every Linux bundle file and every release artifact;
- Windows file hashes, sizes, and PE version metadata;
- resolved Linux dynamic-library dependencies;
- the complete Flutter-generated third-party notice text.

After generation, scan the locked package SBOM with Grype 0.112.0 or newer:

```bash
./tool/scan_vulnerabilities.sh
```

Unlike metadata generation, vulnerability scanning downloads Anchore's current
advisory database. This is an explicit development/release action and is not
part of the installed application's network behavior. The gate fails on a high
or critical match and retains its JSON report for review.

Syft cannot infer every statically linked codec from an opaque native DLL. The
native file manifest and upstream build provenance therefore remain mandatory
alongside the CycloneDX output; an empty binary-component list is not treated
as proof that a bundle has no dependencies. In particular, a zero-match package
scan does not clear an opaque libmpv/FFmpeg DLL.

## Review gates

Before external distribution, review and archive the generated evidence with the
signed artifacts. Confirm that no binary is marked non-redistributable, retain
the corresponding source offer and license texts where LGPL/GPL requires them,
and record the precise mpv/FFmpeg build configuration. Re-run the inventory for
every dependency or toolchain update.

Linux deliberately links the distribution's libmpv. Windows currently uses the
native DLL supplied by `media_kit_libs_windows_video`; its embedded file version
must be reviewed independently of the Dart package version.
