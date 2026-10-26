#!/usr/bin/env bash
# qmllint over the plugin's own QML (vendor/ is checked in its own repo).
#
#   tools/lint-qml.sh            exit 1 when qmllint prints a warning
#
# The shell's modules are imported as qs.Commons / qs.Ui; qmllint needs a
# directory where qs/Commons and qs/Ui exist, so this links them into a temp dir.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
shell=${OMARCHY_SHELL_DIR:-/usr/share/omarchy/shell}
qmllint=${QMLLINT:-/usr/lib/qt6/bin/qmllint}
[[ -x $qmllint ]] || { echo "qmllint not found (set QMLLINT=...)" >&2; exit 2; }
[[ -d $shell/Commons ]] || { echo "Omarchy shell not found at $shell (set OMARCHY_SHELL_DIR=...)" >&2; exit 2; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/qs"
ln -s "$shell/Commons" "$tmp/qs/Commons"
ln -s "$shell/Ui" "$tmp/qs/Ui"
# tests/preview/ is the render harness: valid only inside tools/render-previews.sh.
mapfile -t files < <(git ls-files -co --exclude-standard '*.qml' | grep -v -e '^vendor/' -e '^tests/preview/')
out=$("$qmllint" -I "$tmp" -I /usr/lib/qt6/qml "${files[@]}" 2>&1) || true
[[ -z $out ]] && { echo "qmllint: ${#files[@]} files, no warnings"; exit 0; }
printf '%s\n' "$out"
exit 1
