# Throttle — bandwidth limits for Omarchy

Bar widget that caps download/upload for the whole connection or just for
Heroic and Steam, so a game download doesn't wreck your ping while you play.

![Apps tab](preview.png)

- **Limits** — global download / upload caps on the default-route interface
  (picked automatically, follows Wi-Fi ↔ Ethernet). **Off / 10 / 25 / 50 / 100**
  Mbit/s or **Custom**.
- **Apps** — per-app caps for **Heroic** (incl. `legendary` / `gogdl` / `nile`)
  and **Steam**, matched by their systemd cgroup. **Games-safe** (default) caps
  only TCP transfers past 4 MiB, so game UDP and small requests stay fast.
- **Traffic** — live per-app rates (from `ss`, no root) next to the interface
  total.

**Tab** cycles tabs · **h/l** chips · **j/k** rows · **Enter** acts · **p** pauses

Limits persist and re-apply at login and whenever Heroic or Steam restarts.

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

Start Heroic/Steam from the app launcher, not a terminal (terminal cgroups are
refused). Per-app Traffic rows count TCP only; UDP is in the total.

## Uninstall

```bash
sudo bash ~/.config/omarchy/plugins/yoyo.throttle/scripts/uninstall.sh
omarchy plugin remove yoyo.throttle
rm -rf ~/.local/state/omarchy/yoyo.throttle
```
