#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
linux_bundle="$root/build/linux/x64/release/bundle"
windows_bundle="${WINDOWS_BUNDLE:?Set WINDOWS_BUNDLE to the Windows release bundle directory}"
output="$root/dist/metadata"
powershell="${POWERSHELL:-/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe}"

for command in syft jq sha256sum gzip wslpath; do
  command -v "$command" >/dev/null || {
    echo "Required metadata tool is missing: $command" >&2
    exit 1
  }
done
[[ -x "$powershell" ]] || {
  echo "Windows PowerShell is missing: $powershell" >&2
  exit 1
}
[[ -x "$linux_bundle/klipa_player" ]] || {
  echo "Linux release bundle is missing. Build it first." >&2
  exit 1
}
[[ -f "$windows_bundle/klipa_player.exe" ]] || {
  echo "Windows release bundle is missing: $windows_bundle" >&2
  exit 1
}

case "$output" in
  "$root"/dist/metadata) rm -rf -- "$output" ;;
  *) echo "Refusing unsafe metadata path: $output" >&2; exit 1 ;;
esac
mkdir -p "$output"

raw_version="$(sed -n 's/^version:[[:space:]]*//p' "$root/pubspec.yaml" | head -1)"
version="${raw_version/+/-}"
export SYFT_CHECK_FOR_APP_UPDATE=false

(
  cd "$root"
  syft scan dir:. \
    --exclude "./.git/**" \
    --exclude "./.dart_tool/**" \
    --exclude "./build/**" \
    --exclude "./dist/**" \
    --source-name klipa-player-source \
    --source-version "$version" \
    -q -o "cyclonedx-json=$output/sbom-source.cdx.json"
)

syft scan "dir:$linux_bundle" \
  --source-name klipa-player-linux-x64 \
  --source-version "$version" \
  -q -o "cyclonedx-json=$output/sbom-linux-bundle.cdx.json"
syft scan "dir:$windows_bundle" \
  --source-name klipa-player-windows-x64 \
  --source-version "$version" \
  -q -o "cyclonedx-json=$output/sbom-windows-bundle.cdx.json"

(
  cd "$linux_bundle"
  find . -type f -print0 | sort -z | xargs -0 sha256sum
) > "$output/linux-bundle-sha256.txt"

powershell_script="$(wslpath -w "$root/tool/native_inventory_windows.ps1")"
windows_bundle_native="$(wslpath -w "$windows_bundle")"
windows_inventory_native="$(wslpath -w "$output/windows-native-inventory.json")"
"$powershell" -NoProfile -ExecutionPolicy Bypass -File "$powershell_script" \
  -Bundle "$windows_bundle_native" -Output "$windows_inventory_native"

{
  echo '# Linux dynamic library resolution'
  echo
  find "$linux_bundle" -type f \( -name 'klipa_player' -o -name '*.so' \) -print0 |
    sort -z |
    while IFS= read -r -d '' binary; do
      echo "## ${binary#"$linux_bundle"/}"
      ldd "$binary" 2>&1 || true
      echo
    done
} > "$output/linux-dynamic-libraries.txt"

gzip -dc "$linux_bundle/data/flutter_assets/NOTICES.Z" \
  > "$output/flutter-third-party-notices.txt"

find "$root/dist" -maxdepth 2 -type f \
  \( -name '*.deb' -o -name '*.exe' -o -name '*.zip' \) \
  -print0 | sort -z | xargs -0 sha256sum > "$output/release-artifacts-sha256.txt"

jq -e '.bomFormat == "CycloneDX" and (.components | length > 0)' \
  "$output/sbom-source.cdx.json" >/dev/null
jq -e '.schema == 1 and (.files | length > 0)' \
  "$output/windows-native-inventory.json" >/dev/null

echo "Release metadata: $output"
