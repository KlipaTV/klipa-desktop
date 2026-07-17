# Runtime dependencies

Direct runtime package budget: **13 / 14** (Flutter SDK excluded).

| Package | Why it exists | Native code | License/release gate |
|---|---|---|---|
| `crypto` | Stable SHA-256 identities without custom hashing | No | BSD-3-Clause |
| `ffi` | Auditable native allocation for the narrow DPAPI wrapper | No | BSD-3-Clause; no direct DLL loading |
| `file_selector` | Flutter-maintained native file picker for Windows and Linux | Plugin | BSD-3-Clause; no custom platform dialog code |
| `flutter_secure_storage_linux` | Linux Secret Service plugin for the database key | Linux plugin | BSD-3-Clause; runtime requires libsecret and a desktop keyring |
| `flutter_secure_storage_platform_interface` | Narrow API used to avoid bundling the redundant Windows secure-storage plugin | No | BSD-3-Clause; Linux implementation only |
| `flutter_riverpod` | State and dependency boundaries | No | MIT; stable APIs only |
| `media_kit` | Playback API and libmpv integration | FFI | Audit exact version and transitive behavior |
| `media_kit_libs_video` | Flutter package wiring for platform media runtimes | Yes | Windows release build must replace its downloaded DLL with Klipa's pinned LGPL-profile build |
| `media_kit_video` | Flutter desktop video surface | Native plugin | Memory/lifecycle spike required |
| `path_provider` | Correct per-user app/cache directories | Native plugin | Flutter-maintained; inventory plugin |
| `sqlite3` | Indexed local data and encrypted SQLite native asset | Yes | Use `sqlite3mc`; audit license and binary hash |
| `win32` | DPAPI and minimal Windows integration | FFI/native asset | Pin and review downloaded native artifact |
| `xml` | Event-based XMLTV parser | No | MIT; reject DOCTYPE before parsing |

Removal test: a dependency stays only if replacing it would add more security-
critical or platform-specific code than the package removes.

The committed lockfile is authoritative. Git dependencies, preview versions,
and undocumented dependency overrides are forbidden.
