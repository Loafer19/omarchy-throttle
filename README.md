# Throttle — bandwidth limits for Omarchy

Bar widget that caps download/upload for the whole connection or for single
apps — Heroic and Steam built in, plus any other program (Chrome, Vesktop, a
torrent client…) — so one download doesn't wreck your ping while you play, and
shows where your traffic went today, this week and this month.

Two levels of tabs: **Limits** (Apps · Connection · + Add), **Traffic**
(Live · Today · 7 days · 30 days) and **Settings**.

| Limits › Apps | Limits › Apps › Heroic |
| --- | --- |
| ![Limits › Apps](preview.png) | ![App detail](preview-detail.png) |

- **Limits › Apps** — one compact row per app: state dot, what it is doing
  right now and its ↓ / ↑ caps. **Heroic** (incl. `legendary` / `gogdl` /
  `nile`) and **Steam** are always there. **Enter** opens the app: Download
  and Upload caps — **Off / 10 / 25 / 50 / 100** Mbit/s (the steps are
  configurable) or **Custom**, each with an "≈ MB/s" hint — and **Games-safe**,
  which caps only TCP transfers past 4 MiB so game UDP, calls and small
  requests stay fast. Custom apps have a **Remove** chip (press twice).
  Matched by the app's systemd cgroup.
- **Limits › Connection** — download / upload caps for everything on the
  default-route interface (picked automatically, follows Wi-Fi ↔ Ethernet).
- **Limits › + Add** — any other program (Chrome, Vesktop, a torrent
  client…): one of the ones online right now, or by process name (as in
  `ps -o comm`). Up to 8 apps; a new app opens straight in its detail view.
- **Traffic › Live** — the interface total and a stacked per-app chart of the
  last 90 s, then live per-app rates (from `ss`, no root) with their caps and
  an **Add** chip for programs that aren't limited yet.
- **Traffic › Today / 7 days / 30 days** — how much each app downloaded /
  uploaded, with a per-day chart and the interface total. Collected without
  root every 10 s (TCP byte counters from `ss` + `/sys/class/net`); whatever
  the per-app rows don't explain (game UDP, DNS, headers, root daemons) is the
  **Other / UDP** row. Kept for 35 days (7 / 35 / 90 in Settings) in
  `~/.local/state/omarchy/yoyo.throttle/stats.json` (a few KB).
- **Settings** — live rates in Mbit/s or MB/s, the bar widget style, the
  preset steps, the Games-safe threshold (2 / 4 / 8 / 16 MiB, all apps),
  history length, Clear history, and the helper's install / uninstall command.

| Traffic › Live | Traffic › 7 days | Settings |
| --- | --- | --- |
| ![Live traffic](preview-live.png) | ![Traffic history](preview-stats.png) | ![Settings](preview-settings.png) |

**Tab** cycles the top tabs · **h/l** sub-tabs (or the chips of the row under
the cursor) · **j/k** rows (moving up from the first row reaches the sub-tabs)
· **Enter** opens / toggles / acts · **Esc** goes back from an app, then
closes · **p** pauses

**Bar widget** — the speedometer is accent while limits are active, dimmed
while paused and red on an error; its tooltip lists every cap with its live
rate. Settings › Bar widget adds a red **dot** while a cap is maxed out (≥ 90 %)
or the live download **rate** next to the icon (horizontal bars).

![Bar widget states: icon limiting, idle, dot, rate, paused, error](preview-bar.png)

Limits persist and re-apply at login and whenever a limited app restarts.

## Requirements

Omarchy + `nftables` and `iproute2`. Shaping needs root once: `install.sh`
puts a root-owned copy of `helper/throttle-helper` (strict argument checks) in
`/usr/local/lib/yoyo-throttle/` and a `sudoers.d` rule for that file only.

## Install

```bash
omarchy plugin add https://github.com/Loafer19/omarchy-throttle --enable
sudo bash ~/.config/omarchy/plugins/yoyo.throttle/scripts/install.sh
```

The panel shows the `sudo` command (with Copy) until the helper is installed.

## Usage

Click the speedometer to open the panel. Right-click pauses/resumes all limits.

Games launched from Steam or Heroic share the launcher's cgroup — Games-safe is
what keeps them fast. To take a Steam game out of Steam's caps entirely, set its
launch options to:

```
systemd-run --user --scope --quiet --collect -- %command%
```

Start limited apps from the app launcher, not a terminal: an app started from
a terminal shares the terminal's cgroup, so it is refused (Limits › Apps says
so) rather than capping your shell. Shells, `sudo`, Hyprland, PipeWire and
other session processes can't be added. Per-app Traffic rows count TCP only;
UDP is in the total and in Other.

## Uninstall

```bash
sudo bash ~/.config/omarchy/plugins/yoyo.throttle/scripts/uninstall.sh
omarchy plugin remove yoyo.throttle
rm -rf ~/.local/state/omarchy/yoyo.throttle
```
