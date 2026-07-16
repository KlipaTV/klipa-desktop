#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dart="${DART:-/home/user/flutter/bin/dart}"
output="$root/build/security/klipa_parser_fuzz"
iterations="${FUZZ_ITERATIONS:-20000}"

mkdir -p "$(dirname "$output")"
"$dart" compile exe "$root/tool/fuzz_parsers.dart" -o "$output"
"$output" "$iterations"
