#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flutter="${FLUTTER:-/home/user/flutter/bin/flutter}"
dist="$root/dist/linux"
stage="$dist/stage"
bundle="$root/build/linux/x64/release/bundle"

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

cp -a "$bundle/." "$stage/opt/klipa-player/"
install -m 0644 "$root/packaging/linux/tv.klipa.player.desktop" \
  "$stage/usr/share/applications/tv.klipa.player.desktop"
install -m 0644 "$root/assets/branding/logo_mark.png" \
  "$stage/usr/share/icons/hicolor/512x512/apps/tv.klipa.player.png"

raw_version="$(sed -n 's/^version:[[:space:]]*//p' "$root/pubspec.yaml" | head -1)"
version="${raw_version/+/-}"
installed_size="$(du -sk "$stage" | cut -f1)"
sed -e "s/@VERSION@/$version/g" \
    -e "s/@INSTALLED_SIZE@/$installed_size/g" \
    "$root/packaging/linux/control.in" > "$stage/DEBIAN/control"

mkdir -p "$dist"
package="$dist/klipa-player_${version}_amd64.deb"
dpkg-deb --root-owner-group --build "$stage" "$package"
dpkg-deb --info "$package"
echo "Linux package: $package"
