#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flutter="${FLUTTER:-flutter}"
dist="$root/dist/linux"
stage="$dist/stage"
bundle="$root/build/linux/x64/release/bundle"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  "$flutter" build linux --release
fi
[[ -x "$bundle/klipa_player" ]] || { echo "Linux release bundle is missing." >&2; exit 1; }

# Reproducible packaging
# =====================
# dpkg-deb stores the mtime of every staged file and directory in the archive's
# tar members and compresses them with zstd, so wall-clock timestamps and an
# unpinned compressor make the .deb differ on every run. The package is made
# byte-reproducible by fixing both:
#
#   1. SOURCE_DATE_EPOCH is the only time source dpkg uses. It is derived from
#      the commit timestamp of HEAD (`git log -1 --format=%ct`), so two
#      packagings of the same commit agree even when they run minutes apart.
#      An explicit SOURCE_DATE_EPOCH from the environment wins, which lets a
#      release script rebuild a tagged commit at the time recorded for that
#      tag. Nothing here reads the wall clock.
#   2. The staging tree is normalised to that epoch before packaging. Files
#      copied with `cp -a` keep the bundle's mtimes and directories created
#      with `mkdir` keep the time of the run, so dpkg-deb would otherwise
#      embed both. Every entry is reset to the epoch (see the `find` below).
#
# The compressor is pinned for the same reason: the zstd level is stated
# explicitly so a changed dpkg-deb default cannot alter the bytes, and the
# encoder is limited to one thread because the multithreaded zstd encoder
# reorders the stream as the thread count changes. Level 19 matches
# dpkg-deb's current default, so artifacts keep the size the previous
# toolchain produced.
source_date_epoch="${SOURCE_DATE_EPOCH:-}"
if [[ -z "$source_date_epoch" ]]; then
  source_date_epoch="$(git -C "$root" log -1 --format=%ct 2>/dev/null || true)"
fi
if [[ ! "$source_date_epoch" =~ ^[0-9]+$ ]]; then
  echo "SOURCE_DATE_EPOCH must be a Unix timestamp in seconds; it is unset and could not be derived from Git history." >&2
  exit 1
fi
export SOURCE_DATE_EPOCH="$source_date_epoch"

case "$stage" in
  "$root"/dist/linux/stage) rm -rf -- "$stage" ;;
  *) echo "Refusing unsafe staging path: $stage" >&2; exit 1 ;;
esac
mkdir -p "$stage/DEBIAN" "$stage/opt/klipa-player"
mkdir -p "$stage/usr/share/applications"
mkdir -p "$stage/usr/share/icons/hicolor/512x512/apps"
mkdir -p "$stage/usr/share/doc/klipa-player"

cp -a "$bundle/." "$stage/opt/klipa-player/"
install -m 0644 "$root/packaging/linux/tv.klipa.player.desktop" \
  "$stage/usr/share/applications/tv.klipa.player.desktop"
install -m 0644 "$root/assets/branding/logo_mark.png" \
  "$stage/usr/share/icons/hicolor/512x512/apps/tv.klipa.player.png"
install -m 0644 "$root/LICENSE" \
  "$stage/usr/share/doc/klipa-player/LICENSE"
install -m 0644 "$root/THIRD_PARTY_NOTICES.md" \
  "$stage/usr/share/doc/klipa-player/THIRD_PARTY_NOTICES.md"
cat > "$stage/usr/share/doc/klipa-player/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: klipa-player
Source: https://github.com/KlipaTV/klipa-desktop

Files: *
Copyright: 2026 Klipa contributors
License: LGPL-3.0-or-later
 This package is free software: you can redistribute it and/or modify it
 under the terms of the GNU Lesser General Public License as published by
 the Free Software Foundation, either version 3 of the License, or (at
 your option) any later version.
 .
 On Debian systems, the complete text of the GNU Lesser General Public
 License version 3 can be found in /usr/share/common-licenses/LGPL-3. The
 full text as distributed with this package is in
 /usr/share/doc/klipa-player/LICENSE.
 .
 The Klipa name, logo, and brand identifiers are not covered by this
 license; see TRADEMARKS.md in the source repository.
 .
 Bundled and system third-party components and their licenses are listed
 in /usr/share/doc/klipa-player/THIRD_PARTY_NOTICES.md.
EOF
chmod 0644 "$stage/usr/share/doc/klipa-player/copyright"

raw_version="$(sed -n 's/^version:[[:space:]]*//p' "$root/pubspec.yaml" | head -1)"
version="${raw_version/+/-}"
installed_size="$(du -sk "$stage" | cut -f1)"
sed -e "s/@VERSION@/$version/g" \
    -e "s/@INSTALLED_SIZE@/$installed_size/g" \
    "$root/packaging/linux/control.in" > "$stage/DEBIAN/control"

# Normalise every staged timestamp to the packaging epoch; this is the last
# write to the staging tree before dpkg-deb reads it. -depth visits the contents
# of a directory before the directory itself, so touching a file does not
# re-bump its parent's mtime afterwards, and -h also resets symlink timestamps.
find "$stage" -depth -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +

mkdir -p "$dist"
package="$dist/klipa-player_${version}_amd64.deb"
# Compression is pinned: -Z zstd -z 19 fixes the encoder and level, and
# --threads-max=1 stops the multithreaded zstd encoder from reordering the
# stream. --uniform-compression keeps the control and data members on the same
# settings.
dpkg-deb --root-owner-group --uniform-compression \
  -Z zstd -z 19 --threads-max=1 --build "$stage" "$package"
dpkg-deb --info "$package"
rm -rf -- "$stage"
if [[ -n "${SIGNING_KEY:-}" ]]; then
  command -v gpg >/dev/null || {
    echo "SIGNING_KEY was set but gpg is unavailable." >&2
    exit 1
  }
  gpg --batch --yes --local-user "$SIGNING_KEY" --armor --detach-sign \
    --output "$package.asc" "$package"
  gpg --verify "$package.asc" "$package"
fi
echo "Linux package: $package"
