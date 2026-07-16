#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package="$(find "$root/dist/linux" -maxdepth 1 -name 'klipa-player_*_amd64.deb' -print -quit)"
[[ -n "$package" ]] || { echo "Linux package is missing." >&2; exit 1; }

pid=""
cleanup() {
  if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; fi
  sudo dpkg -r klipa-player >/dev/null 2>&1 || true
}
trap cleanup EXIT

sudo dpkg -i "$package"
/opt/klipa-player/klipa_player > /tmp/klipa-installed-smoke.log 2>&1 &
pid=$!
sleep 5
kill -0 "$pid"

connections="$(ss -Htnp 2>/dev/null | grep -c "pid=$pid," || true)"
if [[ "$connections" != "0" ]]; then
  echo "Clean startup unexpectedly opened $connections TCP connection(s)." >&2
  exit 1
fi

kill "$pid"
wait "$pid" 2>/dev/null || true
pid=""
sudo dpkg -r klipa-player
trap - EXIT
echo "Linux install, clean startup, zero-network, and uninstall smoke passed."
