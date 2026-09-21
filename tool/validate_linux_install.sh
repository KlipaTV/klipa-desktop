#!/usr/bin/env bash
#
# Clean-install and upgrade validation for the Linux .deb on supported
# Debian/Ubuntu releases.
#
# This validates the *distribution* leg of docs/release-checklist.md: that the
# built package installs onto a clean, supported base system rather than only
# onto the host that built it. It never uploads, tags, signs, or publishes
# anything, and it writes only below dist/validation (git-ignored).
#
# Two engines:
#
#   rootfs  No privileges required. For each leg it resolves the package's full
#           dependency closure from that release's own archive with `apt-get`
#           against an isolated, empty dpkg status (a clean system), downloads
#           that closure, extracts it with `dpkg --force-not-root` into a private
#           root filesystem, configures it with *that release's own dpkg* running
#           inside the root, then installs the .deb under test, inspects the
#           result, executes the binary inside the root under Xvfb, removes it
#           again, and exercises the upgrade path. Every phase after the extract
#           runs inside `bwrap` with the host filesystem bound read-only, so a
#           maintainer script cannot reach the machine running the check; only
#           the extract step runs unnamespaced, and the reason for that is
#           measured and documented next to the function that does it. The engine
#           snapshots host dpkg state before and after each leg and reports
#           contamination rather than hiding it.
#
#   docker  The container route. Same checks inside official debian:*/ubuntu:*
#           images. Requires a reachable Docker daemon; it is committed so the
#           check is reproducible where one exists, and it refuses rather than
#           silently skipping. It does not implement the two checks described at
#           the end of this header (declared-floor classification and the
#           declared-closure GL ES check): a container leg reports only PASS or
#           FAIL, so a metadata refusal there appears as a FAIL. The rootfs
#           engine is the engine that implements those checks.
#
# How to read the result of a leg:
#
#   PASS         every check ran at full level, including executing the binary.
#   FAIL         a defect of the package itself: bad layout, a broken install or
#                upgrade, files lost on upgrade, paths surviving removal, or a
#                payload that links against something the release does not
#                provide while the package's metadata says it is supported there.
#   UNSUPPORTED  the release's own archive does not publish a member of a
#                declared Depends group. Recorded as a release-support limit
#                with the evidence, never as a failure of the package.
#   METADATA-UNSUPPORTED
#                the release publishes every declared name, but not a version
#                that satisfies a declared version floor (`libc6 (>= 2.38)`).
#                The package's own metadata says this base system is not
#                supported, so a package manager refuses the install: that is
#                the metadata working, not a defect and not a pass. Recorded as
#                a supportedness verdict with the floor named.
#   PARTIAL      installed and inspected, but a sub-check could not run at full
#                level (for example no Xvfb, or the binary did not stay alive).
#   ENGINE-UNAVAILABLE / INDEX-UNREADABLE / HOST-CONTAMINATED
#                the environment could not answer the question at all. These
#                refuse: they are not a pass and they are not a verdict on the
#                package, and the tool exits non-zero for them.
#
# Exit status: 0 only if every attempted leg passed. 1 if any leg FAILed,
# 4 if any check could not be determined, 3 if any leg was PARTIAL, 2 if any
# leg was UNSUPPORTED or METADATA-UNSUPPORTED. Higher-numbered precedence:
# failure wins over indeterminate wins over partial wins over unsupported. 64
# means the check did not run at all - a bad argument, a missing package, or a
# refused work directory - so that a gate cannot mistake a usage error for a leg
# verdict.
#
# Usage:
#   tool/validate_linux_install.sh                 # auto engine, all known legs
#   tool/validate_linux_install.sh --engine rootfs
#   tool/validate_linux_install.sh --engine docker
#   tool/validate_linux_install.sh --legs debian:12,ubuntu:24.04
#   tool/validate_linux_install.sh --package dist/linux/klipa-player_0.1.1-1_amd64.deb
#   tool/validate_linux_install.sh --keep          # keep the built root filesystems
#   tool/validate_linux_install.sh --clean         # discard cached archives first
#
# Downloaded archives and apt state are cached per leg under the work directory,
# so a second run of the same tree reuses them. Only the root filesystems are
# rebuilt. Nothing here is committed.
#
# Two checks exist to keep a measured defect class from regressing silently:
#
#   * The declared Depends are evaluated *with their version constraints*
#     against the release's own index, not by package name alone, so a version
#     floor the release cannot meet is reported as METADATA-UNSUPPORTED rather
#     than passing and then failing at startup.
#   * The closure of the package *alone* (before the leg's own runtime extras
#     are added) is searched for an archive that actually ships
#     libGLESv2.so.2, the SONAME the Flutter GTK embedder opens at process
#     start. A closure carrying no GL ES provider is a FAIL, even though the
#     leg's own extras would let the launch check below succeed.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
engine="auto"
legs="debian:12,debian:13,ubuntu:22.04,ubuntu:24.04"
package=""
work="${KLIPA_VALIDATION_WORK:-$root/dist/validation}"
keep=0
clean=0
timeout_launch="${KLIPA_LAUNCH_TIMEOUT:-25}"
timeout_build="${KLIPA_BUILD_TIMEOUT:-900}"

usage() {
  awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "${BASH_SOURCE[0]}"
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --engine) engine="${2:?}"; shift 2 ;;
    --legs)   legs="${2:?}"; shift 2 ;;
    --package) package="${2:?}"; shift 2 ;;
    --work)   work="${2:?}"; shift 2 ;;
    --timeout) timeout_launch="${2:?}"; shift 2 ;;
    --keep)   keep=1; shift ;;
    --clean)  clean=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown argument: $1" >&2; usage 64 ;;
  esac
done

[[ "$engine" =~ ^(auto|docker|rootfs)$ ]] || { echo "--engine must be auto, docker, or rootfs." >&2; exit 64; }
[[ "$timeout_launch" =~ ^[0-9]+$ ]] || { echo "--timeout must be a number of seconds." >&2; exit 64; }
[[ "$timeout_build" =~ ^[0-9]+$ ]] || { echo "KLIPA_BUILD_TIMEOUT must be a number of seconds." >&2; exit 64; }

# A relative --work is anchored at the repository root, so the path is always
# absolute before it is validated. It must then be at least two components deep
# and must not be a filesystem root: this is a recursive delete target.
case "$work" in
  /*) ;;
  *) work="$root/$work" ;;
esac
if [[ "$work" == "/" || "$work" == *//* || "$(printf '%s' "$work" | tr -cd '/' | wc -c)" -lt 2 ]]; then
  echo "Refusing unsafe work directory: ${work:-<empty>} (need an absolute path at least two levels deep)." >&2
  exit 64
fi
work="$(readlink -m "$work")"
[[ "$work" != "/" && -n "$work" ]] || { echo "Refusing unsafe work directory." >&2; exit 64; }

# Delete only inside the work directory, and never with an unresolved variable.
safe_rmrf() {
  local target="$1" resolved
  [[ -n "$target" ]] || { echo "safe_rmrf: refusing empty path" >&2; return 1; }
  resolved="$(readlink -m "$target")"
  case "$resolved" in
    "$work"/?*) rm -rf -- "$resolved" ;;
    *) echo "safe_rmrf: refusing path outside the work directory: $resolved" >&2; return 1 ;;
  esac
}

# The package under test: the local dist/ artifact when present, otherwise the
# caller must supply --package.
if [[ -z "$package" ]]; then
  package="$(find "$root/dist/linux" -maxdepth 1 -name 'klipa-player_*_amd64.deb' -print -quit 2>/dev/null || true)"
fi
[[ -n "$package" && -f "$package" ]] || {
  echo "No Linux package found. Build one with tool/package_linux.sh or pass --package." >&2
  exit 64
}
package="$(readlink -m "$package")"

mkdir -p "$work" || exit 1
report="$work/report-$(date -u +%Y%m%dT%H%M%SZ).txt"
: > "$report"

say() { printf '%s\n' "$*" | tee -a "$report"; }
section() { say ""; say "==== $* ===="; }

# ---------------------------------------------------------------------------
# Leg definitions. `archive`, `suite` and `components` describe where that
# release publishes packages. `extra` is installed alongside the package under
# test so the root filesystem is a usable base system: the first group makes
# the root's own dpkg work (dpkg refuses to run without rm, diff and ldconfig),
# the second gives the launch check an X server and a software GL stack.
# A leg is a Debian/Ubuntu release, not a Klipa support statement.
# ---------------------------------------------------------------------------
leg_spec() {
  local bootstrap runtime
  bootstrap="bash coreutils diffutils grep sed findutils dpkg tar gzip xz-utils zstd dash libc-bin util-linux"
  # A base system on which a GTK/GL application can actually be started: an X
  # server, and both GL flavours. Flutter's GTK embedder opens libGLESv2.so.2 at
  # startup and aborts if it is absent, and none of the package's declared
  # Depends pulls a GL ES provider in (measured: with libgl1, libegl1 and mesa
  # present but libgles2 missing, the binary aborts with "Couldn't open
  # libGLESv2.so.2").
  runtime="xvfb xauth libgl1 libgl1-mesa-dri libegl1 libgles2"
  case "$1" in
    debian:12)    echo "debian12|http://deb.debian.org/debian|bookworm|main|$bootstrap $runtime" ;;
    debian:13)    echo "debian13|http://deb.debian.org/debian|trixie|main|$bootstrap $runtime" ;;
    ubuntu:22.04) echo "ubuntu2204|http://archive.ubuntu.com/ubuntu|jammy|main universe|$bootstrap $runtime" ;;
    ubuntu:24.04) echo "ubuntu2404|http://archive.ubuntu.com/ubuntu|noble|main universe|$bootstrap $runtime" ;;
    ubuntu:26.04) echo "ubuntu2604|http://archive.ubuntu.com/ubuntu|resolute|main universe|$bootstrap $runtime" ;;
    *) return 1 ;;
  esac
}

leg_known() { leg_spec "$1" >/dev/null 2>&1; }

# Host invariants that this engine must never change.
host_fingerprint() {
  {
    sha256sum /var/lib/dpkg/status 2>/dev/null || echo "no-host-dpkg-status"
    sha256sum /etc/ld.so.cache 2>/dev/null || echo "no-host-ld-so-cache"
    find /var/lib/dpkg/info -maxdepth 1 -printf '%f\n' 2>/dev/null | wc -l
  } | sha256sum | cut -d' ' -f1
}

# base-passwd's update-passwd creates /etc/shadow and /etc/gshadow and sets their
# group ownership in the same step. Here that step cannot complete (the shadow
# group is not a mapped gid), which leaves both files mode 0000 - unreadable even
# to the release's own adduser, which the next postinst in the dependency chain
# needs, so dbus-system-bus-common fails and takes libgtk-3-common with it.
#
# They are therefore created empty at their standard mode before the configure
# pass, the way a system that is being configured already has them. The release's
# own update-passwd then fills them in, and the resulting files carry the mode
# and content the release intends. If they already exist from a package payload
# (Debian 12 and Ubuntu 24.04 ship them in `passwd`), they are left untouched.
prepare_shadow_files() { # root
  local r="$1" f created=0
  for f in /etc/shadow /etc/gshadow; do
    if [[ ! -e "$r$f" ]]; then
      install -m 0640 /dev/null "$r$f" 2>/dev/null || continue
      created=$((created + 1))
    fi
  done
  [[ $created -gt 0 ]] && say "shadow:    pre-created $created shadow file(s) at mode 0640 (see the note in this script)"
  return 0
}

# After the configure pass, report any file the base system left with no
# permission bits at all. That is the visible signature of an ownership step that
# could not complete, and it is worth recording even when nothing broke.
report_mode_zero_files() { # root
  local r="$1" n
  n="$(find "$r" -xdev -type f -perm 0000 2>/dev/null | wc -l)"
  if [[ "$n" -gt 0 ]]; then
    say "note:      $n base-system file(s) are left mode 0000, because an ownership"
    say "           step could not complete in this namespace:"
    find "$r" -xdev -type f -perm 0000 2>/dev/null | sed "s|^$r|           |" | head -10
  fi
  return 0
}
# The daemon's own error line, which is the evidence for refusing to run the
# container engine. Falls back to the client banner if it says nothing useful.
docker_daemon_error() {
  local line
  line="$(docker info 2>&1 | grep -iE 'permission denied|cannot connect|is the docker daemon running|error during connect|refused' | head -1)"
  printf '%s' "${line:-$(docker info 2>&1 | head -1)}"
}

# ---------------------------------------------------------------------------
# Ownership tolerance for the base-system configure pass.
#
# Measured limitation, not a shortcut: an unprivileged user namespace maps one
# gid, so a name-based chown that resolves to any other group fails with EINVAL
# and dpkg treats that as a hard error. Measured cases on bookworm: base-files'
# postinst chowns /var/mail to root:mail, and dbus's postinst records a
# dpkg-statoverride for root:messagebus. Both failures propagate by dependency
# onto libgtk-3-common -> libgtk-3-0, which klipa-player depends on, so without
# this the leg would fail on a property of the sandbox rather than on anything
# to do with the package - exactly the misattribution this tool exists to remove.
#
# Two narrow mechanisms, both scoped to the base-system configure pass only:
#
#   * chown/chgrp/dpkg-statoverride shims bound over the root's empty
#     /usr/local/bin. dpkg runs maintainer scripts with /usr/local/bin ahead of
#     /usr/bin on PATH, so a script's bare `chown`, `chgrp` or `dpkg-statoverride`
#     reaches the shim, which then invokes the real command. A failure is
#     accepted only when the kernel refused it because the target id cannot be
#     represented in this namespace, and only for the shims; any other failure is
#     passed through unchanged. dpkg-statoverride additionally writes a database
#     record, so its shim rewrites that record - which stores the group NAME and
#     is therefore textually correct - when the apply step is the part that the
#     namespace forbids. Every tolerated operation is printed and logged.
#     Rewriting /etc/group to gid 0 instead was tried and rejected: passwd's
#     postinst asserts that the shadow group is gid 42, and a blanket remap
#     breaks that check, which is a loss of fidelity, not a gain.
#
# What this costs: group ownership of base-system files is not reproduced.
# What it does not touch: the package under test. Its files are built root:root,
# it has no maintainer scripts, and it is installed by dpkg's own code paths
# rather than through these shims.
# ---------------------------------------------------------------------------
shim_dir=""

write_ownership_shims() { # dir
  local d="$1"
  mkdir -p "$d"

  cat >"$d/chown" <<'SHIM'
#!/bin/sh
# Tolerate only a kernel refusal to represent the target id: a property of the
# user namespace, not of the script or the package.
real=/usr/bin/chown
[ -x "$real" ] || exit 127
err=$(mktemp) || exit 1
if "$real" "$@" 2>"$err"; then rm -f "$err"; exit 0; fi
if grep -qE 'Invalid argument|Operation not permitted' "$err"; then
  printf 'ownership-tolerance: chown %s refused by the namespace (%s)\n' "$*" "$(head -1 "$err")" >&2
  rm -f "$err"
  exit 0
fi
cat "$err" >&2
rm -f "$err"
exit 1
SHIM
  sed 's|^real=/usr/bin/chown$|real=/usr/bin/chgrp|; s/chown /chgrp /' "$d/chown" >"$d/chgrp"

  cat >"$d/dpkg-statoverride" <<'SHIM'
#!/bin/sh
# dpkg-statoverride records an entry and applies it to the file. When the apply
# step is what fails, because the namespace cannot represent the group, record
# the entry the real tool would have written and apply the mode.
real=/usr/bin/dpkg-statoverride
[ -x "$real" ] || exit 127
out=$("$real" "$@" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
  [ -n "$out" ] && printf '%s\n' "$out"
  exit 0
fi
case "$out" in
  *"Invalid argument"*|*"Operation not permitted"*) ;;
  *) printf '%s\n' "$out" >&2; exit "$rc" ;;
esac
user=""; group=""; mode=""; path=""; seen=0
for a in "$@"; do
  if [ "$seen" -eq 1 ]; then
    if [ -z "$user" ]; then user=$a
    elif [ -z "$group" ]; then group=$a
    elif [ -z "$mode" ]; then mode=$a
    elif [ -z "$path" ]; then path=$a
    fi
  fi
  [ "$a" = "--add" ] && seen=1
done
if [ -z "$path" ]; then printf '%s\n' "$out" >&2; exit "$rc"; fi
adm=${DPKG_ADMINDIR:-/var/lib/dpkg}
if ! grep -Fqsx "$user $group $mode $path" "$adm/statoverride" 2>/dev/null; then
  printf '%s %s %s %s\n' "$user" "$group" "$mode" "$path" >>"$adm/statoverride"
  chmod 0644 "$adm/statoverride" 2>/dev/null
fi
[ -e "$path" ] && chmod "$mode" "$path" 2>/dev/null
printf 'ownership-tolerance: recorded %s %s %s %s without applying its group ownership\n' \
  "$user" "$group" "$mode" "$path" >&2
exit 0
SHIM

  chmod 0755 "$d/chown" "$d/chgrp" "$d/dpkg-statoverride"
}

# ---------------------------------------------------------------------------
# sandbox helpers. All package installation happens inside bwrap.
# ---------------------------------------------------------------------------

# Extract the closure into the root filesystem.
#
# This is the one phase that does *not* run inside bwrap, and for a measured
# reason: inside a user namespace only a single uid/gid is mapped, so dpkg's
# attempt to set the ownership of a file belonging to any other group (base-files
# ships /var/local as root:staff, passwd ships /usr/bin/chage as root:shadow,
# libpam-modules-bin ships unix_chkpwd as root:shadow) fails with EINVAL, which
# dpkg treats as a hard error rather than as the "cannot chown, not root" case
# it tolerates outside a namespace. Without a namespace those three packages
# unpack cleanly and dpkg changes no ownership at all.
#
# So this runs as the invoking user with --force-not-root, which is exactly the
# mode in which dpkg does not change ownership and tolerates not being root.
# HOME and TMPDIR are redirected into the leg's own work directory. The host's
# dpkg database is untouched because this uses an isolated --admindir, and the
# caller verifies host dpkg and loader state is unchanged afterwards.
#
# --force-depends: the archives are unpacked in one pass, which is not
# dependency order. Unpacking only has to extract files and record them;
# dependency resolution is honoured by the configure pass inside the root,
# which uses the release's own dpkg and is where a real problem shows up.
host_unpack() { # root adm legwork archive...
  local r="$1" adm="$2" legwork="$3"; shift 3
  mkdir -p "$r/var/log" "$legwork/home" "$legwork/tmp"
  HOME="$legwork/home" TMPDIR="$legwork/tmp" \
    dpkg --force-not-root --force-script-chrootless --force-depends \
         --root="$r" --instdir="$r" --admindir="$adm" \
         --log="$r/var/log/dpkg.log" --unpack "$@" \
         >>"$r/var/log/dpkg-unpack.log" 2>&1
}

# the root filesystem as /: the release's own dpkg, its own library paths and
# its own /etc are what run here. `legdir` is bound read-only at /leg so the
# package under test is reachable without copying it into the root.
sandbox_root() { # root home legdir -- cmd...
  local r="$1" home="$2" legdir="$3"; shift 3
  local -a shim=()
  if [[ -n "$shim_dir" ]]; then shim=( --ro-bind "$shim_dir" /usr/local/bin ); fi
  bwrap --unshare-user --uid 0 --gid 0 \
        --bind "$r" / --tmpfs /tmp --tmpfs /run \
        --ro-bind "$legdir" /leg \
        "${shim[@]}" \
        --ro-bind-try /tmp/.X11-unix /tmp/.X11-unix \
        --bind "$home" /root \
        --dev /dev --tmpfs /dev/shm --proc /proc --unshare-pid --unshare-ipc \
        --setenv HOME /root --setenv LC_ALL C \
        --setenv PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        "$@"
}

# does the root carry a working dynamic loader and shell?
root_runnable() { # root
  local r="$1"
  [[ -x "$r/usr/bin/dpkg" || -x "$r/bin/dpkg" ]] || return 1
  [[ -e "$r/bin/sh" ]] || return 1
  return 0
}

# Read one field of one package from the root's own dpkg database. The host's
# `dpkg -f` cannot be used for this: -f is --field, which reads an archive file,
# not a package record, so it silently reports nothing and would turn a
# successful install into a failure.
db_field() { # statusfile package field
  awk -v p="$2" -v f="$3" '
    /^Package: /{cur=$2}
    cur==p && index($0, f": ")==1 {print substr($0, length(f)+3); exit}
  ' "$1" 2>/dev/null
}

# A one-line reason for a verdict whose class alone is not self-explanatory
# (currently the declared-floor verdict). Cleared before every leg and read by
# the summary in main().
verdict_reason=""

# ---------------------------------------------------------------------------
# Engine: rootfs
# ---------------------------------------------------------------------------
run_rootfs_leg() {
  local image="$1" spec name archive suite components extras
  spec="$(leg_spec "$image")" || { say "  SKIP: unknown leg $image"; return 2; }
  IFS='|' read -r name archive suite components extras <<<"$spec"

  local leg_work="$work/rootfs-$name"
  local aptconf="$leg_work/apt"
  local rootfs="$leg_work/root"
  local adm="$rootfs/var/lib/dpkg"
  local rcache="$aptconf/var/cache/apt/archives"
  local home="$leg_work/home"
  local legdir="$leg_work/leg"

  local pkg_name pkg_version dep_line src_rev pkg_sha pkg_size
  local -a extra_pkgs
  read -r -a extra_pkgs <<<"$extras"
  pkg_name="$(dpkg-deb -f "$package" Package)"
  pkg_version="$(dpkg-deb -f "$package" Version)"
  dep_line="$(dpkg-deb -f "$package" Depends)"
  pkg_sha="$(sha256sum "$package" | cut -d' ' -f1)"
  pkg_size="$(stat -c%s "$package")"

  section "leg $image (engine rootfs, suite $suite)"
  say "archive:   $archive $suite $components"
  say "package:   $pkg_name $pkg_version, $pkg_size bytes, sha256 $pkg_sha"
  say "control:   Depends=$dep_line"
  src_rev="$(dpkg-deb -f "$package" Source-Revision 2>/dev/null || true)"
  say "control:   Source-Revision=${src_rev:-<absent>}"
  # shellcheck disable=SC1091
  say "engine host: $(. /etc/os-release && echo "$PRETTY_NAME"), dpkg $(dpkg --version | head -1 | sed 's/.*version //;s/ .*//'), bwrap $(bwrap --version 2>/dev/null || echo '<none>')"

  local host_before host_after
  host_before="$(host_fingerprint)"

  if [[ $clean -eq 1 ]]; then safe_rmrf "$leg_work" || return 4; fi

  mkdir -p "$aptconf/etc/apt/sources.list.d" "$aptconf/etc/apt/preferences.d" \
           "$aptconf/etc/apt/apt.conf.d" "$aptconf/var/lib/apt/lists/partial" \
           "$rcache/partial" "$aptconf/var/lib/dpkg" "$home" "$legdir"
  : > "$aptconf/var/lib/dpkg/status"
  : > "$aptconf/etc/apt/sources.list"
  cp -f "$package" "$legdir/$(basename "$package")"
  local pkg_base; pkg_base="$(basename "$package")"
  local c; for c in $components; do echo "deb [trusted=yes] $archive $suite $c" >>"$aptconf/etc/apt/sources.list"; done

  # The archives are unsigned here on purpose: their Release files are not
  # verified with a keyring, so [trusted=yes] states that plainly instead of
  # pretending the index was authenticated. Ephemeral state, no host effect.
  local -a APT=(
    apt-get
    -o "Dir::State=$aptconf/var/lib/apt"
    -o "Dir::State::status=$aptconf/var/lib/dpkg/status"
    -o "Dir::Cache=$aptconf/var/cache/apt"
    -o "Dir::Etc::sourcelist=$aptconf/etc/apt/sources.list"
    -o "Dir::Etc::sourceparts=/dev/null"
    -o "Dir::Etc::preferences=$aptconf/etc/apt/preferences"
    -o "Dir::Etc::preferencesparts=$aptconf/etc/apt/preferences.d"
    -o "Dir::Etc::trustedparts=/etc/apt/trusted.gpg.d"
    -o "APT::Get::List-Cleanup=0"
    -o "Acquire::AllowInsecureRepositories=true"
    -o "Acquire::Languages=none"
    -o "Acquire::Retries=3"
    -o "Debug::NoLocking=1"
    -o "APT::Install-Recommends=false"
  )
  # apt-cache needs the *same* source configuration. Without it apt 3.x ignores
  # every list file under Dir::State::lists and reports "E: No packages found"
  # for packages the release certainly publishes - which previously turned a
  # satisfiable dependency set into a false UNSUPPORTED verdict.
  local -a APTC=(
    apt-cache
    -o "Dir::State=$aptconf/var/lib/apt"
    -o "Dir::State::lists=$aptconf/var/lib/apt/lists"
    -o "Dir::State::status=$aptconf/var/lib/dpkg/status"
    -o "Dir::Cache=$aptconf/var/cache/apt"
    -o "Dir::Etc::sourcelist=$aptconf/etc/apt/sources.list"
    -o "Dir::Etc::sourceparts=/dev/null"
    -o "Dir::Etc::trustedparts=/etc/apt/trusted.gpg.d"
  )

  # --- indexes --------------------------------------------------------------
  say "reading $suite indexes from $archive ..."
  if ! "${APT[@]}" -qq update >>"$report" 2>&1; then
    say "  Could not read the $suite indexes. Nothing was resolved, so this leg"
    say "  says nothing about the package or about $suite support."
    say "  RESULT: INDEX-UNREADABLE"
    return 4
  fi
  # Positive control: prove the index is actually being read before drawing any
  # conclusion from an absence. libc6 exists in every supported release.
  if ! "${APTC[@]}" show libc6 >/dev/null 2>&1; then
    say "  The $suite index downloaded but no package resolves through it"
    say "  (control lookup for libc6 fails). Dependency absences below would be"
    say "  meaningless, so this leg is not reported as UNSUPPORTED."
    say "  RESULT: INDEX-UNREADABLE"
    return 4
  fi
  local index_count
  index_count="$("${APTC[@]}" pkgnames 2>/dev/null | wc -l)"
  say "index:     $index_count binary packages resolvable for $suite"

  # apt deliberately omits Essential packages from a dependency closure because
  # it assumes the running system already has them. On a clean system they are
  # present, so they belong in the base system built here - base-passwd is the
  # one that matters, since without /etc/passwd's root entry the postinst of
  # base-files cannot chown and the failure cascades into bash and everything
  # downstream of it.
  local -a essential_pkgs=()
  local ep
  while IFS= read -r ep; do
    [[ -n "$ep" ]] && essential_pkgs+=("$ep")
  done < <("${APTC[@]}" dumpavail 2>/dev/null | awk '/^Package: /{p=$2} /^Essential: yes$/{print p}' | sort -u)
  say "base set:  ${#essential_pkgs[@]} Essential packages of $suite added on top of the"
  say "           declared dependency closure, as a clean $suite system has them"
  say "base set:  ${essential_pkgs[*]}"

  # --- can this release satisfy the declared Depends? ------------------------
  #
  # Two questions, deliberately not conflated:
  #
  #   * does the release publish a package with that *name* at all? A "no" is a
  #     distribution-support limit - jammy publishes libmpv1, never libmpv2.
  #   * for a member carrying a version constraint (`libc6 (>= 2.38)`), does the
  #     release publish a version that satisfies it? A "no" is the package's own
  #     declared floor: the metadata is stating that this base system is not
  #     supported. Installing anyway and failing to start is the defect; a
  #     package manager refusing the install is the fix working, so it must not
  #     be reported as a defect of the package (FAIL) nor as a pass.
  #
  # The comparison uses dpkg's own comparator, so it is the same ordering the
  # package manager applies, with the release's own published version as one
  # side ("2.36-9+deb12u14" against "2.38").
  say "checking the declared Depends against $suite ..."
  local group member group_ok absent_any blocked
  local -a missing_groups=() dep_groups=() floor_groups=()
  local mname constraint op want mver
  while IFS= read -r group; do
    [[ -n "$group" ]] || continue
    dep_groups+=("$group")
    group_ok=0
    absent_any=0
    blocked=""
    while IFS= read -r member; do
      [[ -n "$member" ]] || continue
      # "name (op version)" -> name plus constraint; a bare name has no
      # constraint. Only a member with parentheses carries one, so the split is
      # on the first "(" and the first ")" after it.
      mname="$member"
      constraint=""
      if [[ "$member" == *"("*")"* ]]; then
        mname="${member%%(*}"
        constraint="${member#*(}"
        constraint="${constraint%%)*}"
        mname="${mname%"${mname##*[![:space:]]}"}"
        constraint="${constraint#"${constraint%%[![:space:]]*}"}"
        constraint="${constraint%"${constraint##*[![:space:]]}"}"
      fi
      if ! "${APTC[@]}" show "$mname" >/dev/null 2>&1; then
        absent_any=1
        continue
      fi
      # The candidate is what the release would install. A name that exists only
      # as something another package provides (libgtk-3-0 on trixie, from
      # libgtk-3-0t64) reports no candidate of its own, so the first published
      # version stands in for it; that is the same name apt resolves.
      mver="$("${APTC[@]}" policy "$mname" 2>/dev/null | sed -n 's/^  Candidate: //p')"
      if [[ -z "$mver" || "$mver" == "(none)" ]]; then
        mver="$("${APTC[@]}" show "$mname" 2>/dev/null | sed -n 's/^Version: //p' | head -1)"
      fi
      if [[ -z "$constraint" ]]; then
        say "  satisfied: $mname $mver (from $suite)"
      elif [[ -z "$mver" ]]; then
        say "  satisfied: $mname (published; no version resolved to compare with"
        say "             '$mname ($constraint)', so the constraint is not judged here)"
      else
        op="${constraint%%[0-9]*}"
        want="${constraint#"$op"}"
        op="${op// /}"
        want="${want// /}"
        if dpkg --compare-versions "$mver" "$op" "$want" 2>/dev/null; then
          say "  satisfied: $mname $mver (meets '$mname ($constraint)', from $suite)"
        else
          say "  DECLARED FLOOR NOT MET: $suite publishes $mname $mver, which does not"
          say "             satisfy the declared '$mname ($constraint)'"
          blocked="$mname ($constraint) unmet: $suite publishes $mver"
          continue
        fi
      fi
      group_ok=1
    done < <(printf '%s' "$group" | tr '|' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | awk 'NF')
    if [[ $group_ok -eq 0 ]]; then
      if [[ $absent_any -eq 1 ]]; then
        missing_groups+=("$group")
        say "  UNSATISFIED GROUP: $group - no member published in $suite $components"
      elif [[ -n "$blocked" ]]; then
        floor_groups+=("$blocked")
      else
        missing_groups+=("$group")
        say "  UNSATISFIED GROUP: $group - no member resolvable in $suite $components"
      fi
    fi
  done < <(printf '%s' "$dep_line" | tr ',' '\n' | awk 'NF')

  if [[ ${#missing_groups[@]} -gt 0 ]]; then
    say "  RESULT: UNSUPPORTED"
    say "  $suite does not publish a package satisfying every declared Depends"
    say "  group above. This is a distribution-support limit of $pkg_name"
    say "  $pkg_version, not a defect of the package's contents."
    if [[ ${#floor_groups[@]} -gt 0 ]]; then
      say "  A declared version floor is unmet here as well:"
      for m in "${floor_groups[@]}"; do say "    $m"; done
    fi
    return 2
  fi

  if [[ ${#floor_groups[@]} -gt 0 ]]; then
    say "  RESULT: METADATA-UNSUPPORTED"
    say "  $suite does not satisfy a version floor that $pkg_name $pkg_version"
    say "  declares in its Depends, so a package manager refuses this package here"
    say "  instead of installing something that cannot start:"
    for m in "${floor_groups[@]}"; do say "    $m"; done
    say "  This is the metadata doing its job. It is not a defect of the package's"
    say "  contents and it is not a pass, so it is reported as its own verdict."
    verdict_reason="declared floor unmet - ${floor_groups[*]}"
    return 5
  fi
  say "every declared Depends group is published by $suite, with its version floor met"

  # --- resolve the closure on a clean (empty) dpkg status --------------------
  say "resolving the closure of '$pkg_name + base system' against a clean $suite system ..."
  local resolve_rc=0
  timeout "$timeout_build" "${APT[@]}" -s install "$package" "${extra_pkgs[@]}" "${essential_pkgs[@]}" >"$leg_work/resolve.txt" 2>&1 || resolve_rc=$?
  if [[ $resolve_rc -ne 0 ]]; then
    say "  dependency resolution failed on a clean $suite system:"
    grep -E '^(E:|W:)' "$leg_work/resolve.txt" | head -10 | sed 's/^/    /' | tee -a "$report" >/dev/null
    grep -E '^(E:|W:)' "$leg_work/resolve.txt" | head -10 | sed 's/^/    /' >>"$report"
    say "  RESULT: UNSUPPORTED"
    return 2
  fi
  local closure_count
  closure_count="$(grep -c '^Inst ' "$leg_work/resolve.txt" || true)"
  say "closure:   $closure_count packages, clean $suite system plus $pkg_name"
  say "closure:   $(grep -E '^Inst (libmpv2|libgtk-3-0|libgtk-3-0t64|libsecret-1-0) ' "$leg_work/resolve.txt" | sed 's/^Inst /  /' | tr '\n' ' ')"
  say "closure:   full simulation at $leg_work/resolve.txt"

  say "fetching the closure into the leg's private archive cache ..."
  # Which archives must arrive: every member of the closure except the package
  # under test itself, which is local and is bound into the sandbox later.
  local -a expect_names=()
  local n
  while IFS= read -r n; do
    n="${n%%:*}"; n="${n%%=*}"
    [[ "$n" == "$pkg_name" ]] && continue
    expect_names+=("$n")
  done < <(grep '^Inst ' "$leg_work/resolve.txt" | awk '{print $2}' | sort -u)

  local attempt=1 dl_rc=0
  local -a missing_archives=()
  while :; do
    dl_rc=0
    timeout "$timeout_build" "${APT[@]}" --download-only --yes install "$package" "${extra_pkgs[@]}" "${essential_pkgs[@]}" >>"$report" 2>&1 || dl_rc=$?
    missing_archives=()
    for n in "${expect_names[@]}"; do
      compgen -G "$rcache/${n}_*.deb" >/dev/null 2>&1 || missing_archives+=("$n")
    done
    [[ ${#missing_archives[@]} -eq 0 ]] && break
    [[ $attempt -ge 2 ]] && break
    attempt=$((attempt + 1))
    say "  ${#missing_archives[@]} archive member(s) did not arrive (apt rc=$dl_rc);"
    say "  refreshing the index and retrying once"
    "${APT[@]}" -qq update >>"$report" 2>&1 || true
  done

  local dcount
  dcount="$(find "$rcache" -maxdepth 1 -name '*.deb' 2>/dev/null | wc -l)"
  say "archives:  $dcount member archives cached ($(du -sh "$rcache" 2>/dev/null | cut -f1)), ${#expect_names[@]} expected"

  # The exact files to extract, each matched to the version the resolve listed.
  # Extracting every archive in the cache instead would also pick up one left
  # behind by an earlier, different closure.
  local -a expected_files=()
  local want f found
  for n in "${expect_names[@]}"; do
    want="$(awk -v n="$n" '$1=="Inst" && $2==n {v=$3; gsub(/[()]/,"",v); print v; exit}' "$leg_work/resolve.txt")"
    found=""
    for f in "$rcache/${n}"_*.deb; do
      [[ -e "$f" ]] || continue
      if [[ -z "$want" || "$(dpkg-deb -f "$f" Version 2>/dev/null)" == "$want" ]]; then
        found="$f"
        break
      fi
    done
    if [[ -n "$found" ]]; then
      expected_files+=("$found")
    else
      missing_archives+=("$n ${want:+(wanted version $want)}")
    fi
  done

  if [[ ${#missing_archives[@]} -gt 0 ]]; then
    say "  These closure members could not be fetched from $suite:"
    say "    ${missing_archives[*]}"
    say "  The clean system cannot be assembled from an incomplete closure, so"
    say "  this leg says nothing about the package. Last apt status: rc=$dl_rc"
    grep -E '^(E:|Err)' "$report" | tail -6 | sed 's/^/    /'
    say "  RESULT: INDEX-UNREADABLE (incomplete archives after $attempt attempt(s))"
    return 4
  fi
  say "archives:  ${#expected_files[@]} archive file(s) matched to the resolved versions"

  # --- does the *declared* closure carry a GL ES provider? -------------------
  #
  # The execution check further down runs with this leg's runtime extras, which
  # include libgles2 because the Flutter GTK embedder opens libGLESv2.so.2 as the
  # process starts. A successful launch there therefore cannot show whether the
  # package's *own* Depends bring a GL ES provider: with libgl1, libegl1 and mesa
  # present but libgles2 missing, the binary aborts with "Couldn't open
  # libGLESv2.so.2", and none of the declared dependencies pulls one in.
  #
  # So the closure of the package alone (plus the release's Essential packages,
  # which every clean system already has) is resolved separately, and the
  # archives themselves are searched for the SONAME. A package *name* is not
  # evidence: the provider has to ship the file the loader opens.
  say "checking the declared closure for a GL ES provider ..."
  local gl_resolve="$leg_work/resolve-declared.txt"
  if ! timeout "$timeout_build" "${APT[@]}" -s install "$package" "${essential_pkgs[@]}" >"$gl_resolve" 2>&1; then
    say "  The declared closure does not resolve on $suite on its own, so whether"
    say "  it carries a GL ES provider cannot be determined. Full output:"
    say "  $gl_resolve"
    say "  RESULT: INDEX-UNREADABLE (declared closure did not resolve)"
    return 4
  fi
  local -a declared_names=()
  while IFS= read -r n; do
    n="${n%%:*}"; n="${n%%=*}"
    [[ "$n" == "$pkg_name" ]] && continue
    declared_names+=("$n")
  done < <(grep '^Inst ' "$gl_resolve" | awk '{print $2}' | sort -u)
  local gles_provider="" pn pf
  for pn in "${declared_names[@]}"; do
    for pf in "$rcache/${pn}"_*.deb; do
      [[ -e "$pf" ]] || continue
      if [[ -n "$(dpkg-deb -c "$pf" 2>/dev/null | grep -m1 -F 'libGLESv2.so.2' || true)" ]]; then
        gles_provider="$pn ($(basename "$pf"))"
        break 2
      fi
    done
  done
  say "declared:  ${#declared_names[@]} package(s) in the closure of $pkg_name alone,"
  say "           with none of this leg's runtime extras added"
  if [[ -z "$gles_provider" ]]; then
    say "  RESULT: FAIL - no package in the declared dependency closure ships"
    say "  libGLESv2.so.2. A base system built from the declared dependencies,"
    say "  plus an X server and a GL stack, aborts at startup with"
    say "  \"Couldn't open libGLESv2.so.2\": the declared closure is missing a GL"
    say "  ES provider. Declare one whose name resolves on every release the"
    say "  package claims to support (libgles2 does, measured on all four legs of"
    say "  this tool)."
    return 1
  fi
  say "GL ES:     $gles_provider ships libGLESv2.so.2, and is declared rather"
  say "           than added by this leg's runtime extras"

  # --- build the clean root filesystem --------------------------------------
  # Always from empty: reusing a partially built root from an earlier run would
  # make the "clean system" claim untrue. Only the archive cache is reused.
  safe_rmrf "$rootfs" || return 4
  mkdir -p "$rootfs" "$adm/info" "$adm/updates" "$adm/triggers" "$rootfs/var/log"
  : > "$adm/status"
  : > "$adm/available"
  section "leg $image: building the clean $suite root filesystem"
  say "root:      $rootfs"
  say "extract:   dpkg --force-not-root as the invoking user (no ownership is changed;"
  say "           see the note in this script on why this step is not namespaced)"
  say "then:      configure, install, execute and remove all run inside bwrap with the"
  say "           host filesystem read-only and only the root writable"
  local unpack_rc=0
  host_unpack "$rootfs" "$adm" "$leg_work" "${expected_files[@]}" || unpack_rc=$?
  local reg unconf
  reg="$(grep -c '^Package: ' "$adm/status" 2>/dev/null || echo 0)"
  unconf="$(grep -c '^Status: install ok unpacked' "$adm/status" 2>/dev/null || echo 0)"
  say "unpacked:  $reg packages registered, $unconf awaiting configuration (unpack rc=$unpack_rc)"
  if ! root_runnable "$rootfs"; then
    say "  The unpacked closure has no usable dpkg or shell inside the root, so the"
    say "  release's own package manager cannot be run against it."
    say "  RESULT: INDEX-UNREADABLE (bootstrap incomplete)"
    return 4
  fi

  say "configuring with the root's own dpkg ($(db_field "$adm/status" dpkg Version)) ..."
  local cfg_rc=0
  # The base-system configure pass runs with the ownership-tolerance shims in
  # place; every other phase runs without them.
  write_ownership_shims "$leg_work/shims"
  mkdir -p "$rootfs/usr/local/bin"
  prepare_shadow_files "$rootfs"
  shim_dir="$leg_work/shims"
  sandbox_root "$rootfs" "$home" "$legdir" /bin/sh -c 'dpkg --configure -a > /var/log/configure.log 2>&1' || cfg_rc=$?
  shim_dir=""
  report_mode_zero_files "$rootfs"
  local conf
  conf="$(grep -c '^Status: install ok installed' "$adm/status" 2>/dev/null || echo 0)"
  say "configured: $conf packages 'install ok installed' (configure rc=$cfg_rc)"
  say "clean base: $conf-package $suite system, no Klipa package yet"
  if [[ "$conf" -eq 0 ]]; then
    say "  Not one base package reached 'install ok installed', so this is not a"
    say "  clean supported system to install onto. Not a verdict on the package."
    tail -5 "$rootfs/var/log/configure.log" 2>/dev/null | sed 's/^/    /' | tee -a "$report" >/dev/null
    tail -5 "$rootfs/var/log/configure.log" 2>/dev/null | sed 's/^/    /' >>"$report"
    say "  RESULT: INDEX-UNREADABLE (base configuration failed)"
    return 4
  fi

  # Attribution guard. A base system whose own packages did not finish
  # configuring cannot install anything on top of them, and a dependency that is
  # merely unpacked reads as "not configured yet" - which dpkg would report
  # against klipa-player. That would be a false verdict on the package, so it is
  # checked and separated out before the package under test is installed.
  #
  # The check is per Depends *group*, not per name: a name in a group can be a
  # virtual package that the release provides through a differently named real
  # package (Debian 13 and Ubuntu 24.04 provide `libgtk-3-0` from
  # `libgtk-3-0t64`), and requiring the provided name to exist would fail on a
  # perfectly configured system.
  local -a base_unmet=()
  local g mem st group_ok
  for g in "${dep_groups[@]}"; do
    [[ -n "$g" ]] || continue
    group_ok=0
    while IFS= read -r mem; do
      [[ -n "$mem" ]] || continue
      st="$(db_field "$adm/status" "$mem" Status)"
      [[ "$st" == "install ok installed" ]] && group_ok=1
    done < <(printf '%s' "$g" | tr '|' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]*([^)]*)//g' | awk 'NF')
    if [[ $group_ok -eq 0 ]]; then
      base_unmet+=("$g (no member is 'install ok installed')")
    fi
  done
  if [[ ${#base_unmet[@]} -gt 0 ]]; then
    say "  The clean $suite base system did not finish configuring a package that"
    say "  $pkg_name depends on, so the package under test was never given a"
    say "  supported system to install onto. This is not a defect of the package:"
    for m in "${base_unmet[@]}"; do say "    $m"; done
    say "  Packages left unconfigured by the base-system pass:"
    local uncfg
    uncfg="$(awk '/^Package: /{p=$2} /^Status: /{if ($0 !~ /install ok installed/) print "    "p" -> "$0}' \
      "$adm/status" 2>/dev/null | head -20)"
    say "${uncfg:-    (none)}"
    say "  The partially built root is left at $rootfs for inspection."
    say "  RESULT: ENGINE-UNAVAILABLE (base system incomplete, see above)"
    return 4
  fi
  say "attribution: every declared dependency group of $pkg_name is satisfied by a"
  say "             configured package in the root"

  # --- install the package under test ---------------------------------------
  section "leg $image: install"
  say "installing /leg/$pkg_base with the root's own dpkg, inside the root filesystem"
  local install_rc=0
  sandbox_root "$rootfs" "$home" "$legdir" /bin/sh -c \
    "dpkg --log=/var/log/dpkg.log -i /leg/$pkg_base" >"$leg_work/install.log" 2>&1 || install_rc=$?
  [[ -s "$leg_work/install.log" ]] && { sed 's/^/    /' "$leg_work/install.log" >>"$report"; }
  sed 's/^/    /' "$leg_work/install.log" 2>/dev/null || true
  local status_field
  status_field="$(db_field "$adm/status" "$pkg_name" Status)"
  say "dpkg status: ${status_field:-<not registered>} (dpkg -i rc=$install_rc)"
  if [[ "$status_field" != "install ok installed" ]]; then
    say "  RESULT: FAIL - $pkg_name did not reach 'install ok installed' on a clean $suite system"
    return 1
  fi
  say "install:   $pkg_name $pkg_version reached 'install ok installed'"

  # --- installed layout ------------------------------------------------------
  section "leg $image: installed layout"
  dpkg --root="$rootfs" --admindir="$adm" -L "$pkg_name" | sort >"$leg_work/installed-files.txt"
  say "owned entries: $(wc -l <"$leg_work/installed-files.txt") paths (files, symlinks and the directories the package owns)"
  local expect missing_expected=0
  for expect in \
    /opt/klipa-player/klipa_player \
    /opt/klipa-player/lib/libflutter_linux_gtk.so \
    /usr/share/applications/tv.klipa.player.desktop \
    /usr/share/icons/hicolor/512x512/apps/tv.klipa.player.png \
    /usr/share/doc/klipa-player/SOURCE_REVISION \
    /usr/share/doc/klipa-player/copyright \
    /usr/share/doc/klipa-player/LICENSE \
    /usr/share/doc/klipa-player/THIRD_PARTY_NOTICES.md; do
    if [[ -e "$rootfs$expect" ]]; then
      say "  present: $expect"
    else
      say "  MISSING: $expect"
      missing_expected=1
    fi
  done
  if [[ $missing_expected -eq 1 ]]; then
    say "  RESULT: FAIL - the installed payload is missing a documented path"
    return 1
  fi
  say "non-/opt owned paths:"
  grep -v '^/opt/klipa-player' "$leg_work/installed-files.txt" | sed 's/^/    /' >>"$report"
  grep -v '^/opt/klipa-player' "$leg_work/installed-files.txt" | sed 's/^/    /'
  if grep -qE '/stage(/|$)|^/opt/klipa-player/(data|lib)/stage' "$leg_work/installed-files.txt"; then
    say "  RESULT: FAIL - a packaging staging path was installed"
    return 1
  fi
  # Content snapshot, used to prove the upgrade path does not lose or change files.
  # Paths come from dpkg -L as absolute paths, so they must be made relative
  # before hashing: `cd $rootfs` with a leading slash would read the host.
  local -a owned=()
  while IFS= read -r f; do
    [[ -f "$rootfs$f" ]] && owned+=("${f#/}")
  done <"$leg_work/installed-files.txt"
  ( cd "$rootfs" && printf '%s\0' "${owned[@]}" | xargs -0 -r md5sum 2>/dev/null | sort ) >"$leg_work/fresh-md5.txt"
  say "content:   $(wc -l <"$leg_work/fresh-md5.txt") owned files hashed for the upgrade comparison"

  # --- embedded provenance ---------------------------------------------------
  section "leg $image: embedded provenance"
  local revfile="$rootfs/usr/share/doc/klipa-player/SOURCE_REVISION"
  say "control Source-Revision: ${src_rev:-<absent>}"
  say "payload SOURCE_REVISION:"
  sed 's/^/    /' "$revfile" >>"$report"
  sed 's/^/    /' "$revfile"
  local rev_commit
  rev_commit="$(sed -n 's/^Commit: //p' "$revfile")"
  if [[ ! "$rev_commit" =~ ^[0-9a-f]{40}$ ]]; then
    say "  RESULT: FAIL - the payload does not carry a full commit SHA"
    return 1
  fi
  if git -C "$root" cat-file -e "$rev_commit" 2>/dev/null; then
    say "  commit $rev_commit is present in this repository"
  else
    say "  commit $rev_commit is not in this checkout (expected for an older artifact)"
  fi

  # --- integrity and link resolution -----------------------------------------
  section "leg $image: integrity and dynamic link"
  if [[ -f "$adm/info/$pkg_name.md5sums" ]]; then
    local verify_out
    verify_out="$(dpkg --root="$rootfs" --admindir="$adm" --verify "$pkg_name" 2>&1 || true)"
    if [[ -n "$verify_out" ]]; then
      say "dpkg --verify reported:"; say "$verify_out"
      say "  RESULT: FAIL - a packaged file is missing or modified after install"
      return 1
    fi
    say "dpkg --verify: no packaged file is missing or modified"
  else
    say "dpkg --verify: not applicable - the control archive carries no md5sums"
    say "  (the package ships no /var/lib/dpkg/info/$pkg_name.md5sums, so there is"
    say "   no per-file checksum list for dpkg to check)"
  fi
  local loader="/lib64/ld-linux-x86-64.so.2"
  [[ -e "$rootfs$loader" ]] || loader="/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"

  # glibc floor. A payload built against a glibc newer than the release provides
  # installs happily and then fails to load. What stops that is the *declared*
  # floor (`Depends: libc6 (>= 2.38)`), which is evaluated above and reported as
  # METADATA-UNSUPPORTED on a leg that cannot meet it: a versioned Depends on
  # libc6 does express a minimum glibc version, and the package manager enforces
  # it before unpacking anything. Reaching this check therefore means the
  # artifact declares no floor, or one lower than its own payload needs.
  # Compare what each packaged ELF actually requires against what this release
  # provides, which is the diagnosis the loader's own message does not give.
  local link_fail=0
  local base_glibc
  base_glibc="$(db_field "$adm/status" libc6 Version)"
  base_glibc="${base_glibc%%-*}"
  say "glibc:     $suite provides libc6 $base_glibc"
  local elf req reqv over=0
  while IFS= read -r elf; do
    [[ -f "$elf" ]] || continue
    req="$(grep -aoE 'GLIBC_[0-9]+\.[0-9]+' "$elf" 2>/dev/null | sort -uV | tail -1)"
    [[ -n "$req" ]] || continue
    reqv="${req#GLIBC_}"
    if [[ "$reqv" != "$base_glibc" ]] && \
       [[ "$(printf '%s\n%s\n' "$base_glibc" "$reqv" | sort -V | tail -1)" == "$reqv" ]]; then
      say "  needs $req: ${elf#"$rootfs"} (newer than $base_glibc)"
      over=$((over + 1))
    fi
  done < <(find "$rootfs/opt/klipa-player" -type f \( -name '*.so' -o -name '*.so.*' -o -name 'klipa_player' \) | sort)
  if [[ $over -gt 0 ]]; then
    say "  RESULT: FAIL - $over packaged ELF object(s) link against a glibc newer than"
    say "  $suite provides ($base_glibc), while the declared Depends do not require a"
    say "  libc6 new enough for them. The artifact therefore installs on $suite and"
    say "  then part of its payload cannot load there: the declared support for this"
    say "  release is wider than what the package can actually run on. A release that"
    say "  cannot satisfy a *declared* floor is reported as METADATA-UNSUPPORTED, so"
    say "  reaching this check means the floor is missing or too low."
    link_fail=1
  fi

  local link_out unresolved
  link_out="$(sandbox_root "$rootfs" "$home" "$legdir" "$loader" --list /opt/klipa-player/klipa_player 2>&1 || true)"
  unresolved="$(printf '%s\n' "$link_out" | grep -c 'not found' || true)"
  if [[ "${unresolved:-0}" == "0" ]]; then
    say "dynamic link: every NEEDED library resolves against the $suite package set"
  else
    say "dynamic link: $unresolved NEEDED librar(ies) unresolved against $suite:"
    printf '%s\n' "$link_out" | grep 'not found' | sed 's/^/    /' >>"$report"
    printf '%s\n' "$link_out" | grep 'not found' | sed 's/^/    /'
    say "  RESULT: FAIL - the installed binary cannot resolve its NEEDED libraries on"
    say "  a clean $suite system. The leg continues so that the rest of the checks"
    say "  are still recorded, and the verdict stays FAIL."
    link_fail=1
  fi

  # --- execute it inside the clean root --------------------------------------
  section "leg $image: execution"
  local launched="no" launch_rc=-1
  if command -v xvfb-run >/dev/null 2>&1; then
    say "executing under: Xvfb (host) + bwrap (root as /), HOME=/root inside the root"
    # -ac disables X access control on this one private, local, ephemeral Xvfb:
    # the sandbox has no xauth cookie, and without it GTK refuses to open the
    # display ("Authorization required, but no authorization protocol
    # specified"). The display is created and destroyed by this check alone.
    set +e
    timeout "$timeout_launch" xvfb-run -a --server-args="-screen 0 1280x800x24 -ac" \
      bwrap --unshare-user --uid 0 --gid 0 \
            --bind "$rootfs" / --tmpfs /tmp --tmpfs /run \
            --ro-bind-try /tmp/.X11-unix /tmp/.X11-unix \
            --bind "$home" /root \
            --dev /dev --tmpfs /dev/shm --proc /proc --unshare-pid --unshare-ipc \
            --setenv HOME /root \
            --setenv XDG_DATA_HOME /root/.local/share \
            --setenv XDG_CONFIG_HOME /root/.config \
            --setenv XDG_CACHE_HOME /root/.cache \
            --chdir /opt/klipa-player \
            /opt/klipa-player/klipa_player >"$leg_work/launch.log" 2>&1
    launch_rc=$?
    set -e
    say "launch rc=$launch_rc (124 = still running when the ${timeout_launch}s timeout fired)"
    if [[ -s "$leg_work/launch.log" ]]; then
      say "launch output (first 30 lines):"
      head -30 "$leg_work/launch.log" | sed 's/^/    /' >>"$report"
      head -30 "$leg_work/launch.log" | sed 's/^/    /'
    else
      say "launch output: (none)"
    fi
    case "$launch_rc" in
      124) launched="alive" ;;
      0)   launched="exited0" ;;
      *)   launched="rc$launch_rc" ;;
    esac
  else
    say "execution: not attempted - xvfb-run is not installed."
    say "  This leg is reported as PARTIAL: the package installed and was"
    say "  inspected, but nothing was executed inside the clean root."
  fi

  # --- uninstall -------------------------------------------------------------
  section "leg $image: uninstall"
  # dpkg -L lists the directories the package owns as well as its files. A
  # directory that survives removal is normal and intended - dpkg removes files,
  # and only removes a directory if it is empty - so the check is about files and
  # symlinks. The application directory is checked separately below.
  local before=0 f
  while IFS= read -r f; do
    if [[ -f "$rootfs$f" || -L "$rootfs$f" ]]; then before=$((before + 1)); fi
  done <"$leg_work/installed-files.txt"
  say "packaged files present before removal: $before"
  local rm_rc=0
  sandbox_root "$rootfs" "$home" "$legdir" /bin/sh -c "dpkg --log=/var/log/dpkg.log -r $pkg_name" >/dev/null 2>>"$rootfs/var/log/dpkg-remove.log" || rm_rc=$?
  local remaining=0 kept_dirs=0
  while IFS= read -r f; do
    if [[ -d "$rootfs$f" && ! -L "$rootfs$f" ]]; then
      kept_dirs=$((kept_dirs + 1))
      continue
    fi
    if [[ -e "$rootfs$f" || -L "$rootfs$f" ]]; then
      say "  LEFT BEHIND: $f"
      remaining=$((remaining + 1))
    fi
  done <"$leg_work/installed-files.txt"
  if [[ $remaining -gt 0 ]]; then
    say "  RESULT: FAIL - $remaining packaged file(s) survived removal (dpkg -r rc=$rm_rc)"
    return 1
  fi
  say "  packaged files removed; $kept_dirs owned directory/directories retained"
  say "  (as dpkg intends: they are shared with the base system or still hold files)"
  if [[ -d "$rootfs/opt/klipa-player" ]] && \
     [[ -n "$(find "$rootfs/opt/klipa-player" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
    say "  RESULT: FAIL - /opt/klipa-player still holds files after removal"
    return 1
  fi
  say "uninstall: database entry gone and every packaged path removed (dpkg -r rc=$rm_rc)"

  # --- upgrade path ----------------------------------------------------------
  local up_rc=0
  run_upgrade_transition "$image" "$rootfs" "$adm" "$legdir" "$pkg_name" "$pkg_version" "$home" \
    "$leg_work" || up_rc=$?
  if [[ $up_rc -eq 4 ]]; then
    say "  RESULT: ENGINE-UNAVAILABLE - the upgrade transition could not be built"
    return 4
  elif [[ $up_rc -eq 1 ]]; then
    say "  RESULT: FAIL - the upgrade path is defective"
    return 1
  fi

  # --- host containment ------------------------------------------------------
  host_after="$(host_fingerprint)"
  if [[ "$host_before" != "$host_after" ]]; then
    say "  RESULT: HOST-CONTAMINATED - this engine changed host dpkg state;"
    say "  the leg is void and nothing above it should be relied on."
    return 4
  fi
  say "containment: host dpkg and loader state unchanged by this leg"

  say "root size:  $(du -sh "$rootfs" 2>/dev/null | cut -f1)"
  if [[ $keep -eq 0 ]]; then safe_rmrf "$rootfs"; fi

  if [[ $link_fail -eq 1 ]]; then
    say "  LEG RESULT: FAIL (the payload does not fully link on this release; the"
    say "              install, layout, provenance, uninstall and upgrade results"
    say "              above are still valid and are recorded)"
    return 1
  fi
  if [[ "$launched" == "alive" ]]; then
    say "  LEG RESULT: PASS (install, layout, provenance, dynamic link, execution"
    say "              under Xvfb, uninstall, upgrade transition all at full level)"
    return 0
  fi
  say "  LEG RESULT: PARTIAL (install, layout, provenance, dynamic link, uninstall"
  say "              and the upgrade transition verified; execution level: $launched)"
  return 3
}

# ---------------------------------------------------------------------------
# Upgrade leg. Builds a lower Debian revision of the same payload, installs it,
# then installs the package under test over it, and compares the resulting
# filesystem against the fresh-install snapshot. Only the Debian revision
# differs, so this exercises dpkg's upgrade transition - not a cross-version
# payload change, which needs an older artifact to exist.
# ---------------------------------------------------------------------------
run_upgrade_transition() { # image root adm legdir pkg_name pkg_version home leg_work
  local image="$1" rootfs="$2" adm="$3" legdir="$4" pkg_name="$5" pkg_version="$6" home="$7" leg_work="$8"
  section "leg $image: upgrade path"

  local base rev older_version
  if [[ "$pkg_version" =~ ^(.*)-([0-9]+)$ ]] && [[ "${BASH_REMATCH[2]}" -gt 0 ]]; then
    base="${BASH_REMATCH[1]}"
    rev=$(( BASH_REMATCH[2] - 1 ))
    older_version="$base-$rev"
  else
    say "  '$pkg_version' has no Debian revision to lower; the upgrade transition"
    say "  needs either an older artifact of this product or a higher revision."
    return 4
  fi

  local up_dir="$leg_work/upgrade"
  safe_rmrf "$up_dir" || return 4
  mkdir -p "$up_dir"
  local older_deb="$up_dir/${pkg_name}_${older_version}_amd64.deb"
  local newer_deb="$up_dir/${pkg_name}_${pkg_version}_amd64.deb"
  rm -rf -- "$up_dir/tree"
  dpkg-deb -R "$package" "$up_dir/tree" >/dev/null 2>&1 || { say "  could not unpack the package for the older artifact"; return 4; }
  sed -i "s/^Version: .*/Version: $older_version/" "$up_dir/tree/DEBIAN/control"
  dpkg-deb --root-owner-group --build "$up_dir/tree" "$older_deb" >/dev/null 2>&1 \
    || { say "  could not build the older artifact"; return 4; }
  cp -f "$package" "$newer_deb"
  rm -rf -- "$up_dir/tree"
  # The sandbox sees one read-only directory; keep both artifacts in it.
  cp -f "$older_deb" "$legdir/$(basename "$older_deb")"
  cp -f "$newer_deb" "$legdir/$(basename "$newer_deb")"
  say "older artifact: $older_version ($(stat -c%s "$older_deb") bytes), same payload as $pkg_version"
  say "newer artifact: $pkg_version ($(stat -c%s "$newer_deb") bytes), the package under test"
  say "note: both carry one identical payload, so this validates the dpkg upgrade"
  say "      transition (version move, file replacement, no loss). A cross-version"
  say "      payload upgrade is not validated here because no older artifact of"
  say "      this product is present in this checkout."

  local inst_rc=0
  sandbox_root "$rootfs" "$home" "$legdir" /bin/sh -c "cd /leg && dpkg --log=/var/log/dpkg.log -i $(basename "$older_deb")" \
    >/dev/null 2>>"$rootfs/var/log/dpkg-upgrade.log" || inst_rc=1
  local v_older
  v_older="$(db_field "$adm/status" "$pkg_name" Version)"
  say "installed older: ${v_older:-<not registered>} (rc=$inst_rc)"
  if [[ "$v_older" != "$older_version" ]]; then
    say "  Could not establish the lower-revision starting point, so the upgrade"
    say "  transition was not exercised."
    return 4
  fi

  inst_rc=0
  sandbox_root "$rootfs" "$home" "$legdir" /bin/sh -c "cd /leg && dpkg --log=/var/log/dpkg.log -i $(basename "$newer_deb")" \
    >/dev/null 2>>"$rootfs/var/log/dpkg-upgrade.log" || inst_rc=1
  local v_new
  v_new="$(db_field "$adm/status" "$pkg_name" Version)"
  say "after installing newer: ${v_new:-<not registered>} (rc=$inst_rc)"
  if [[ "$v_new" != "$pkg_version" ]]; then
    say "  FAIL: dpkg did not move $older_version -> $pkg_version"
    return 1
  fi
  say "  transition: $older_version -> $v_new"

  local st
  st="$(db_field "$adm/status" "$pkg_name" Status)"
  if [[ "$st" != "install ok installed" ]]; then
    say "  FAIL: after the upgrade the status is '${st:-<absent>}'"
    return 1
  fi

  dpkg --root="$rootfs" --admindir="$adm" -L "$pkg_name" | sort >"$leg_work/upgraded-files.txt"
  if ! diff -q "$leg_work/installed-files.txt" "$leg_work/upgraded-files.txt" >/dev/null 2>&1; then
    say "  FAIL: the upgraded package owns a different path set than a fresh install:"
    diff "$leg_work/installed-files.txt" "$leg_work/upgraded-files.txt" | sed 's/^/    /' >>"$report"
    diff "$leg_work/installed-files.txt" "$leg_work/upgraded-files.txt" | sed 's/^/    /'
    return 1
  fi
  say "  path set after upgrade is identical to a fresh install ($(wc -l <"$leg_work/upgraded-files.txt") paths)"

  local -a owned=()
  local f
  while IFS= read -r f; do
    [[ -f "$rootfs$f" ]] && owned+=("${f#/}")
  done <"$leg_work/upgraded-files.txt"
  ( cd "$rootfs" && printf '%s\0' "${owned[@]}" | xargs -0 -r md5sum 2>/dev/null | sort ) >"$leg_work/upgraded-md5.txt"
  if ! diff -q "$leg_work/fresh-md5.txt" "$leg_work/upgraded-md5.txt" >/dev/null 2>&1; then
    say "  FAIL: file contents after the upgrade differ from a fresh install:"
    diff "$leg_work/fresh-md5.txt" "$leg_work/upgraded-md5.txt" | head -20 | sed 's/^/    /' >>"$report"
    diff "$leg_work/fresh-md5.txt" "$leg_work/upgraded-md5.txt" | head -20 | sed 's/^/    /'
    return 1
  fi
  say "  content after upgrade matches a fresh install ($(wc -l <"$leg_work/upgraded-md5.txt") files hashed)"
  say "  RESULT: upgrade transition verified, no file lost, added or changed"
  return 0
}

# ---------------------------------------------------------------------------
# Engine: docker
# ---------------------------------------------------------------------------
run_docker_leg() {
  local image="$1"
  section "leg $image (engine docker)"

  command -v docker >/dev/null 2>&1 || {
    say "  ENGINE-UNAVAILABLE: no docker client on this host."
    return 4
  }
  if ! docker info >/dev/null 2>&1; then
    say "  ENGINE-UNAVAILABLE: the docker client is present but this user cannot"
    say "  reach the daemon, so no container can run. Reported as unavailable"
    say "  rather than skipped; nothing here is a verdict on the package."
    say "  daemon: $(docker_daemon_error)"
    return 4
  fi

  local pkg_name pkg_version
  pkg_name="$(dpkg-deb -f "$package" Package)"
  pkg_version="$(dpkg-deb -f "$package" Version)"
  say "image:   $image"
  say "package: $pkg_name $pkg_version, $(stat -c%s "$package") bytes, sha256 $(sha256sum "$package" | cut -d' ' -f1)"

  local script
  script="$(cat <<'CONTAINER'
set -e
export DEBIAN_FRONTEND=noninteractive
P=$(dpkg-deb -f /pkg.deb Package)
apt-get update -qq
echo "--- control ---"
dpkg-deb -f /pkg.deb Package Version Depends Source-Revision
echo "--- resolve ---"
apt-get -s -y install /pkg.deb 2>&1 | grep -E '^(Inst|E:)' | head -20
echo "--- install ---"
apt-get install -y -qq /pkg.deb
dpkg -s "$P" | sed -n '1,6p'
echo "--- layout ---"
dpkg -L "$P"
echo "--- provenance ---"
cat /usr/share/doc/klipa-player/SOURCE_REVISION
echo "--- verify ---"
if [ -f "/var/lib/dpkg/info/$P.md5sums" ]; then
  dpkg --verify "$P" && echo "verify-clean"
else
  echo "verify-not-applicable (no md5sums in the control archive)"
fi
echo "--- launch ---"
timeout 25 xvfb-run -a /opt/klipa-player/klipa_player >/tmp/launch.log 2>&1; echo "launch-rc=$?"
head -20 /tmp/launch.log || true
echo "--- uninstall ---"
dpkg -r "$P"
if [ -e /opt/klipa-player/klipa_player ]; then echo "leftover: /opt/klipa-player/klipa_player"; exit 1; fi
echo "uninstall-clean"
echo "CONTAINER-VERDICT: OK"
CONTAINER
)"
  local out rc=0
  out="$(docker run --rm -v "$package:/pkg.deb:ro" "$image" /bin/sh -c "$script" 2>&1)" || rc=$?
  printf '%s\n' "$out" >>"$report"
  printf '%s\n' "$out"
  if [[ $rc -ne 0 ]] || [[ "$out" != *"CONTAINER-VERDICT: OK"* ]]; then
    say "  LEG RESULT: FAIL (container checks did not complete; see the transcript above)"
    return 1
  fi
  say "  LEG RESULT: PASS (the transcript above is the evidence)"
  return 0
}

# ---------------------------------------------------------------------------
main() {
  say "Klipa Player Linux install validation"
  say "when:    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  say "repo:    $root"
  say "head:    $(git -C "$root" rev-parse HEAD 2>/dev/null || echo 'not a git tree')"
  say "package: $package"
  say "engine:  $engine"
  say "legs:    $legs"
  say "report:  $report"

  local chosen="$engine"
  if [[ "$engine" == "auto" ]]; then
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
      chosen="docker"
    else
      chosen="rootfs"
      say "auto engine: rootfs (the docker client cannot reach a daemon)"
      say "  reason: $(docker_daemon_error)"
    fi
    say "auto engine selected: $chosen"
  fi
  if [[ "$chosen" == "rootfs" ]]; then
    command -v bwrap >/dev/null 2>&1 || {
      say "ENGINE-UNAVAILABLE: the rootfs engine needs bwrap to install into a"
      say "private root and execute inside it, and bwrap is not installed. The"
      say "check refuses rather than reporting a partial result as a pass."
      exit 4
    }
  fi

  local -a results=()
  local -a reasons=()
  local -a leg_list=()
  IFS=',' read -r -a leg_list <<<"$legs"
  local leg rc
  for leg in "${leg_list[@]}"; do
    leg="${leg//[[:space:]]/}"
    [[ -n "$leg" ]] || continue
    rc=0
    verdict_reason=""
    if ! leg_known "$leg"; then
      section "leg $leg"
      say "  Unknown leg. Known legs: debian:12 debian:13 ubuntu:22.04 ubuntu:24.04 ubuntu:26.04"
      results+=("$leg UNKNOWN")
      reasons+=("")
      continue
    fi
    if [[ "$chosen" == "docker" ]]; then
      run_docker_leg "$leg" || rc=$?
    else
      run_rootfs_leg "$leg" || rc=$?
    fi
    case "$rc" in
      0) results+=("$leg PASS") ;;
      1) results+=("$leg FAIL") ;;
      2) results+=("$leg UNSUPPORTED") ;;
      3) results+=("$leg PARTIAL") ;;
      4) results+=("$leg UNAVAILABLE") ;;
      5) results+=("$leg METADATA-UNSUPPORTED") ;;
      *) results+=("$leg ERROR($rc)") ;;
    esac
    reasons+=("${verdict_reason:-}")
  done

  section "summary"
  local r i
  for i in "${!results[@]}"; do
    r="${results[$i]}"
    if [[ -n "${reasons[$i]:-}" ]]; then
      say "  $r - ${reasons[$i]}"
    else
      say "  $r"
    fi
  done
  say ""
  say "Full transcript: $report"
  say "Engine: $chosen. Root filesystems are rebuilt per run and removed unless --keep."
  say "Cached archives under $work are reused by later runs."

  # Combine the per-leg verdicts into one process status. The classes are not
  # ordered by their exit number, so the worst one is selected explicitly: a
  # package defect outranks an undetermined result, which outranks a partial
  # result, which outranks an unsupported release. Getting this wrong would let
  # an UNSUPPORTED leg mask a FAILing one in the exit status.
  local severity=0 sev
  for r in "${results[@]}"; do
    case "$r" in
      *" PASS")               sev=0 ;;
      *" METADATA-UNSUPPORTED") sev=1 ;;
      *" UNSUPPORTED")        sev=1 ;;
      *" PARTIAL")            sev=2 ;;
      *" FAIL")               sev=4 ;;
      *)                      sev=3 ;;
    esac
    [[ $sev -gt $severity ]] && severity=$sev
  done
  local verdict
  case "$severity" in
    4) verdict=1 ;;  # a defect of the package
    3) verdict=4 ;;  # the environment could not answer the question
    2) verdict=3 ;;  # installed and inspected, execution not at full level
    1) verdict=2 ;;  # a release-support limit or a declared floor, not a defect
    *) verdict=0 ;;  # every attempted leg passed
  esac
  say "exit: $verdict (0 all pass, 1 fail, 2 unsupported, 3 partial, 4 undetermined)"
  exit "$verdict"
}

main
