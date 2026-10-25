#!/usr/bin/env bash
# One-time setup for yoyo.throttle. Run once, with sudo:
#
#   sudo bash scripts/install.sh
#
# Installs a COPY of helper/throttle-helper (root-owned, so the user-writable
# plugin folder can never change what runs as root) and a sudoers.d rule that
# lets only you run only that file without a password.
#
#   --prefix DIR   install under DIR instead of / (packaging/tests; no chown)
set -euo pipefail
umask 022
prefix=""
[[ ${1:-} == --prefix ]] && { prefix=${2:?--prefix needs a directory}; shift 2; }
(( $# == 0 )) || { echo "usage: sudo bash install.sh [--prefix DIR]" >&2; exit 2; }

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
src=$here/../helper/throttle-helper
libdir=$prefix/usr/local/lib/yoyo-throttle
helper=$libdir/throttle-helper
sudoers=$prefix/etc/sudoers.d/yoyo-throttle
installed_path=/usr/local/lib/yoyo-throttle/throttle-helper

if [[ -z $prefix ]]; then
  [[ $(id -u) == 0 ]] || { echo "Run me with sudo: sudo bash $0" >&2; exit 1; }
  user=${SUDO_USER:-}
  [[ -n $user && $user != root ]] || { echo "Run via sudo from your normal user (SUDO_USER is empty/root)." >&2; exit 1; }
else
  user=${SUDO_USER:-$(id -un)}
fi
[[ $user =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { echo "Unexpected user name: $user" >&2; exit 1; }

for bin in nft tc ip; do
  command -v "$bin" >/dev/null || { echo "Missing $bin (install nftables / iproute2)." >&2; exit 1; }
done
bash -n "$src"

own=(); [[ -z $prefix ]] && own=(-o root -g root)
install -d -m 0755 "${own[@]}" "$libdir"
install -m 0755 "${own[@]}" "$src" "$helper"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
cat > "$tmp" <<RULE
# yoyo.throttle (Omarchy bar widget): lets $user apply/clear bandwidth limits.
# The helper validates every argument; remove with scripts/uninstall.sh.
$user ALL=(root) NOPASSWD: $installed_path
RULE
if command -v visudo >/dev/null; then
  visudo -cqf "$tmp" || { echo "visudo rejected the rule; nothing installed in sudoers.d" >&2; exit 1; }
fi
install -d -m 0750 "${own[@]}" "$prefix/etc/sudoers.d"
install -m 0440 "${own[@]}" "$tmp" "$sudoers"

echo "Installed $helper"
echo "Installed $sudoers  ($user may run the helper without a password)"
[[ -n $prefix ]] || echo "Done. Open the Throttle panel — limits apply within a few seconds."
