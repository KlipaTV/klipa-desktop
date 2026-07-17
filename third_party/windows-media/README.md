# Windows media runtime

Klipa's Windows release uses a locally built `libmpv-2.dll`. Public release
artifacts must not use the opaque DLL downloaded by
`media_kit_libs_windows_video`.

`tool/build_windows_media.sh` checks out the pinned upstream
`mpv-winbuild-cmake` revision, applies `mpv-winbuild-lgpl.patch`, builds the
64-bit DLL, and writes release evidence below `dist/windows-media/current/`.
The patch disables mpv's GPL mode and removes GPL codec/filter dependencies
from the build graph. FFmpeg remains version-3 LGPL; nonfree components are
never enabled. The renderer keeps libplacebo's D3D11/OpenGL path while omitting
Vulkan, glslang, and shaderc. SPIR-V Cross is linked in its standard static mode
for D3D11 shader translation.

The generated directory contains:

- `libmpv-2.dll` and its SHA-256;
- the upstream build-wrapper commit and applied patch;
- the exact revision of every fetched source repository;
- the CMake configuration and build logs;
- pinned build-tool versions;
- collected license files; and
- when `--archive-source` is passed, the corresponding-source archive needed
  for external distribution.

The build deliberately does not invoke the upstream aggregate `download`
target: that target fetches every optional package, including GPL packages the
Klipa profile does not compile. Ninja instead downloads only dependencies
reachable from the `gcc` and patched `mpv` targets. Two-way build concurrency
and four bounded attempts tolerate transient GitHub checkout failures without
creating an unbounded retry loop.

The Windows application build replaces the package-supplied DLL only when this
evidence is complete. Re-run the application tests, native inventory, SBOM,
vulnerability scan, installer smoke test, and Authenticode verification after
every media-runtime rebuild.

This profile intentionally omits DVD navigation, AviSynth/VapourSynth,
Rubber Band, x264, x265, Xvid, Lua, JavaScript, SDL gamepad, terminal graphics,
and other features that are unnecessary for Klipa's M3U/HLS/MPEG-TS playback
boundary.
