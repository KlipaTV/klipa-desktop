# Runtime dependencies

Direct runtime package budget: **11 / 12** (Flutter SDK excluded).

| Package | Why it exists | Native code | License/release gate |
|---|---|---|---|
| `crypto` | Stable SHA-256 identities without custom hashing | No | BSD-3-Clause |
| `ffi` | Auditable native allocation for the narrow DPAPI wrapper | No | BSD-3-Clause; no direct DLL loading |
| `filepicker_windows` | Small maintained Win32 common-file dialog wrapper | FFI | BSD-3-Clause; uses the same reviewed `win32` dependency |
| `flutter_riverpod` | State and dependency boundaries | No | MIT; stable APIs only |
| `media_kit` | Playback API and libmpv integration | FFI | Audit exact version and transitive behavior |
| `media_kit_libs_video` | Pinned native media binaries | Yes | Full binary/codec/license audit before distribution |
| `media_kit_video` | Flutter Windows video surface | Windows plugin | Memory/lifecycle spike required |
| `path_provider` | Correct per-user app/cache directories | Windows plugin | Flutter-maintained; inventory plugin |
| `sqlite3` | Indexed local data and encrypted SQLite native asset | Yes | Use `sqlite3mc`; audit license and binary hash |
| `win32` | DPAPI and minimal Windows integration | FFI/native asset | Pin and review downloaded native artifact |
| `xml` | Event-based XMLTV parser | No | MIT; reject DOCTYPE before parsing |

Removal test: a dependency stays only if replacing it would add more security-
critical or platform-specific code than the package removes.

The committed lockfile is authoritative. Git dependencies, preview versions,
and undocumented dependency overrides are forbidden.
