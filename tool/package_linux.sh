#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flutter="${FLUTTER:-flutter}"
dist="$root/dist/linux"
stage="$dist/stage"
bundle="$root/build/linux/x64/release/bundle"

# --- Reproducible packaging --------------------------------------------------
#
# dpkg-deb consumes exactly one time source, SOURCE_DATE_EPOCH, for the mtimes
# of every member of control.tar and data.tar *and* for the ar headers of the
# .deb itself. Left unset it uses the wall clock, so two builds of one commit
# never agree. Derive it from the commit so builds of that commit are stable,
# and let an explicit value override it for a tagged rebuild. Validate it as an
# integer: an epoch that is not a number silently becomes the wall clock.
if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
  epoch="$SOURCE_DATE_EPOCH"
else
  epoch="$(git -C "$root" log -1 --format=%ct)"
fi
[[ "$epoch" =~ ^[0-9]+$ ]] || {
  echo "SOURCE_DATE_EPOCH must be a non-negative integer, got: $epoch" >&2
  exit 1
}
export SOURCE_DATE_EPOCH="$epoch"

# The package states the revision it was built from, in the control archive and
# in the payload, so provenance does not rest on the version string alone.
revision="${SOURCE_REVISION:-$(git -C "$root" rev-parse --verify 'HEAD^{commit}')}"
[[ "$revision" =~ ^[0-9a-f]{40}$ ]] || {
  echo "SOURCE_REVISION must be a full 40-character commit SHA, got: $revision" >&2
  exit 1
}

# Pin the compressor instead of inheriting host-dependent defaults. 19 is the
# level dpkg-deb itself uses for zstd: recompressing the extracted data.tar with
# the zstd CLI at each level matches the built member byte-for-byte at 19, so
# stating it keeps the artifact size stable. --threads-max=1 removes the
# dependency on the build host's CPU count.
zstd_level="${DEB_ZSTD_LEVEL:-19}"
[[ "$zstd_level" =~ ^[0-9]+$ ]] || {
  echo "DEB_ZSTD_LEVEL must be a non-negative integer, got: $zstd_level" >&2
  exit 1
}

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  "$flutter" build linux --release
fi
[[ -x "$bundle/klipa_player" ]] || { echo "Linux release bundle is missing." >&2; exit 1; }

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
    -e "s/@SOURCE_REVISION@/$revision/g" \
    "$root/packaging/linux/control.in" > "$stage/DEBIAN/control"
cat > "$stage/usr/share/doc/klipa-player/SOURCE_REVISION" <<EOF
Klipa Player Debian package

Version: $version
Commit: $revision
Source: https://github.com/KlipaTV/klipa-desktop
Source-Date-Epoch: $epoch

This package was built from the commit above. Verify with:
  git cat-file -e <commit> && git log -1 --format=%H
EOF
chmod 0644 "$stage/usr/share/doc/klipa-player/SOURCE_REVISION"

# Last write before packaging. `cp -a` preserves the bundle's old mtimes and
# `mkdir`/`install` stamp the time of the run, while dpkg-deb only clamps mtimes
# *newer* than the epoch - older ones survive untouched. Normalise the whole
# tree ourselves: -depth touches a directory after its contents (touching the
# parent first would re-bump it a moment later), -h covers symlinks.
find "$stage" -depth -exec touch -h -d "@$epoch" {} +

mkdir -p "$dist"
package="$dist/klipa-player_${version}_amd64.deb"
dpkg-deb --root-owner-group \
  --uniform-compression -Z zstd -z "$zstd_level" --threads-max=1 \
  --build "$stage" "$package"
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
echo "Source revision: $revision"
echo "SOURCE_DATE_EPOCH: $epoch"
