// Shared by Model.js (QML) and scripts/backend.sh (read as JSON after the
// "var CONFIG = " prefix), so keep this file a single plain JSON object.
// "presets" are the built-in apps (always listed, can't be removed);
// "limits" bound what settings may hold (the root helper accepts at most 8 apps).
// "units" (mbit|mbyte) is how live rates read, "barWidget" (icon|dot|rate) what
// the bar shows, "steps" the rate chips, "keepDays" how long history is kept.
var CONFIG = {
  "enabled": true,
  "downMbit": 0,
  "upMbit": 0,
  "units": "mbit",
  "barWidget": "icon",
  "steps": [10, 25, 50, 100],
  "keepDays": 35,
  "apps": {
    "heroic": { "downMbit": 0, "upMbit": 0, "gamesSafe": true, "bulkMiB": 4 },
    "steam": { "downMbit": 0, "upMbit": 0, "gamesSafe": true, "bulkMiB": 4 }
  },
  "presets": {
    "heroic": { "label": "Heroic", "procs": ["heroic", "legendary", "gogdl", "nile"] },
    "steam": { "label": "Steam", "procs": ["steam", "steamwebhelper"] }
  },
  "custom": { "downMbit": 0, "upMbit": 0, "gamesSafe": false, "bulkMiB": 4 },
  "limits": { "maxApps": 8, "maxProcs": 4, "keepDays": 35 },
  "denyProcs": ["systemd", "bash", "sh", "zsh", "fish", "dash", "sudo", "su", "Hyprland", "Xwayland", "uwsm", "dbus-daemon", "dbus-broker", "quickshell", "pipewire", "wireplumber"]
};
