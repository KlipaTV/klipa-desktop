#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sbom="$root/dist/metadata/sbom-source.cdx.json"
report="$root/dist/metadata/vulnerability-scan.json"
temporary="$report.tmp"

command -v grype >/dev/null || {
  echo "Grype is required for the vulnerability scan." >&2
  exit 1
}
[[ -f "$sbom" ]] || {
  echo "Generate release metadata before scanning vulnerabilities." >&2
  exit 1
}

export GRYPE_CHECK_FOR_APP_UPDATE=false
rm -f -- "$temporary"
if ! grype "sbom:$sbom" -q --fail-on high -o json > "$temporary"; then
  mv -f -- "$temporary" "$report"
  echo "High or critical dependency vulnerability detected: $report" >&2
  exit 1
fi
mv -f -- "$temporary" "$report"
echo "Dependency vulnerability scan passed: $report"
