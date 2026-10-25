#!/usr/bin/env bash
# Removes everything scripts/install.sh added and any active shaping:
#
#   sudo bash scripts/uninstall.sh
#
# Your settings (~/.local/state/omarchy/yoyo.throttle) are left alone; delete
# that folder yourself if you want a clean slate.
set -euo pipefail
prefix=""
[[ ${1:-} == --prefix ]] && { prefix=${2:?--prefix needs a directory}; shift 2; }
helper=$prefix/usr/local/lib/yoyo-throttle/throttle-helper
if [[ -z $prefix ]]; then
  [[ $(id -u) == 0 ]] || { echo "Run me with sudo: sudo bash $0" >&2; exit 1; }
  if [[ -x $helper ]]; then "$helper" clear || echo "warning: clear failed; reboot drops any leftover shaping" >&2; fi
  rm -rf /run/yoyo-throttle
fi
rm -f "$prefix/etc/sudoers.d/yoyo-throttle"
rm -rf "$prefix/usr/local/lib/yoyo-throttle"
echo "Removed the helper, its sudoers rule, and any active limits."
