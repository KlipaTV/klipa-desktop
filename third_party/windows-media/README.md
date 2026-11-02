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
the Vulkan loader, glslang, and shaderc; libplacebo still compiles its Vulkan
stubs, so the Vulkan headers are a build-time dependency only. FFmpeg's TLS is
Schannel, which checks certificates against the Windows store: the player sets
`tls-verify=yes`, and OpenSSL or mbedTLS, with no CA store on Windows, fail
every HTTPS handshake (measured on the pub package's DLL, 2026-11-02). OpenSSL
stays in the graph for libssh, libsrt and libarchive. SPIR-V Cross is linked in its standard static mode
for D3D11 shader translation.

The pinned mpv-winbuild-cmake revision is `bda10a2` (2026-10-30). Its own
package patches are kept in step with the upstream sources it fetches, which
are not pinned, so an old revision stops building as those sources move: the
June revision this file first named (`04283f7`) failed on fontconfig's patch
and on a GCC snapshot that no longer exists. The current revision builds GCC
from the 14.4.0 release with a SHA-512 checked against gcc.gnu.org and the GNU
keyring (2026-11-02).

`apply_lgpl_profile.py` is how the patch is made: on a clean checkout of the
pinned revision, apply the libplacebo and spirv-cross hunks of the previous
patch, run the script, and save `git diff`. It removes the GPL and unused
dependencies and switches their options off by meaning rather than by line, so
moving the pin does not depend on unchanged context. It also pins the one
moving download of the toolchain: cppwinrt reads `Windows.winmd` from
windows-rs `master`, and the patch fetches windows-rs `8786f59`, the revision
`master` served when the pinned commit was made (4,653,056 bytes, SHA-256
`06cbb9a5febd5f5d9d06a31f2643bb95f7935a5a43f7d287c6f356ef1dd45ac8`).

`check_lgpl_graph.py` runs on every build after the patch is applied: it walks
the whole dependency graph of mpv and stops the build if a GPL package, a
package the profile removes, or a GPL option of a reachable library is in it.
Its closure listing is kept as `lgpl-graph.txt`. The build also stops if any
compiled component has no license text in `licenses/`.

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
mpv's libcurl stream backend (with curl's HTTP/2, HTTP/3 and DNS stack),
libzvbi (teletext; its library has GPL-2-only files), libarchive's LZO support
(liblzo2 is GPL-2.0), Little CMS's GPL-3.0 fast_float and threaded plugins,
and other features that are unnecessary for Klipa's M3U/HLS/MPEG-TS playback
boundary.
