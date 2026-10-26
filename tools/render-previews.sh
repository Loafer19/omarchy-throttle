#!/usr/bin/env bash
# Render the marketplace/README previews offscreen with made-up data:
#   tools/render-previews.sh [OUT_DIR]      (default: the repo root)
# Runs the real Panel.qml and BarWidget.qml in Quickshell (QT_QPA_PLATFORM=offscreen) against
# tests/preview/FakeStore.qml, a made-up store, so nothing from this machine
# (interfaces, apps, traffic) ends up in the images. Needs qs and the
# Omarchy shell (Commons, Ui); skips cleanly without them. Colors follow the
# active Omarchy theme.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(mkdir -p "${1:-$root}" && cd "${1:-$root}" && pwd)
shell_dir=${OMARCHY_PATH:-/usr/share/omarchy}/shell
command -v qs >/dev/null 2>&1 || { echo "SKIP  render-previews (no qs)"; exit 0; }
[[ -d $shell_dir/Ui && -d $shell_dir/Commons ]] || { echo "SKIP  render-previews (no Omarchy shell at $shell_dir)"; exit 0; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/throttle-previews.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
cfg=$tmp/cfg
mkdir -p "$cfg/plugin"
ln -s "$shell_dir/Commons" "$cfg/Commons"
# Ui is Omarchy's, except KeyboardPanel: a layer-shell window cannot map
# offscreen, so a stub draws the same card in a plain Item.
mkdir -p "$cfg/Ui"
for f in "$shell_dir"/Ui/*; do ln -s "$f" "$cfg/Ui/"; done
rm -f "$cfg/Ui/KeyboardPanel.qml"
cp "$root/tests/preview/KeyboardPanel.qml" "$cfg/Ui/KeyboardPanel.qml"
tar -C "$root" --exclude=.git --exclude='./preview*.png' -cf - . | tar -C "$cfg/plugin" -xf -
cp "$root/tests/preview/shell.qml" "$cfg/shell.qml"
cp "$root/tests/preview/bar.qml" "$cfg/bar.qml"

render() { # render FILE ENTRY [VAR=VALUE ...]
  local name=$1 file=$out/$1 entry=$cfg/$2 log=$tmp/${1//\//_}.log
  shift 2
  env "$@" PREVIEW_OUT="$file" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    QT_SCALE_FACTOR="${PREVIEW_SCALE:-2}" timeout 40 qs -p "$entry" > "$log" 2>&1 || true
  if grep -q '^.*saved ' "$log" && [[ -s $file ]]; then
    echo "saved $file"
  else
    echo "FAIL  render $name" >&2; tail -n 20 "$log" >&2; return 1
  fi
}
render preview.png shell.qml PREVIEW_TAB=limits PREVIEW_SUB=apps
render preview-detail.png shell.qml PREVIEW_TAB=limits PREVIEW_SUB=apps PREVIEW_DETAIL=heroic
render preview-live.png shell.qml PREVIEW_TAB=traffic PREVIEW_SUB=live
render preview-stats.png shell.qml PREVIEW_TAB=traffic PREVIEW_SUB=week
render preview-settings.png shell.qml PREVIEW_TAB=settings
render preview-bar.png bar.qml
