// Made-up store for tools/render-previews.sh: the shape of Service.qml with
// fixed apps, traffic, history and stats. Nothing is read from this machine;
// every action is a no-op.
import QtQuick

QtObject {
  id: root
  property string mode: "icon"
  property bool paused: false
  property bool setup: false
  property string error: ""
  property real heroicDown: 1235000
  property bool noLimit: false

  property var cfg: ({ enabled: !paused, downMbit: 0, upMbit: 0, units: "mbit", barWidget: mode, steps: [10, 25, 50, 100], keepDays: 35, apps: {
    heroic: { downMbit: 10, upMbit: 0, gamesSafe: true, bulkMiB: 4, label: "Heroic", procs: ["heroic"], preset: true },
    steam: { downMbit: 25, upMbit: 0, gamesSafe: true, bulkMiB: 4, label: "Steam", procs: ["steam"], preset: true },
    chrome: { downMbit: 50, upMbit: 10, gamesSafe: false, bulkMiB: 4, label: "Chrome", procs: ["chrome"], preset: false },
    qbittorrent: { downMbit: 25, upMbit: 5, gamesSafe: false, bulkMiB: 4, label: "qBittorrent", procs: ["qbittorrent"], preset: false } } })
  property var status: ({ helper: setup ? "missing" : "installed", helperPath: "/usr/local/lib/yoyo-throttle/throttle-helper", iface: "eth0",
    mode: "apply", applied: true, live: { ifb: true, egress: true }, error: error, changed: false,
    apps: [ { key: "heroic", running: true, cgroups: ["a", "b"], refused: [], shared: [] },
            { key: "steam", running: true, cgroups: ["c"], refused: [], shared: [] },
            { key: "chrome", running: true, cgroups: ["d", "e"], refused: [], shared: [] },
            { key: "qbittorrent", running: false, cgroups: [], refused: [], shared: [] } ] })
  property var traffic: ({ iface: { name: "eth0", down: 2410000, up: 96000 }, apps: [
    { name: "Steam", key: "steam", proc: "steamwebhelper", own: true, down: 1190000, up: 21000, conns: 4 },
    { name: "Heroic", key: "heroic", proc: "heroic", own: true, down: heroicDown, up: 9000, conns: 2 },
    { name: "Chrome", key: "chrome", proc: "chrome", own: true, down: 160000, up: 24000, conns: 14 },
    { name: "spotify", key: "", proc: "spotify", own: true, down: 41000, up: 3000, conns: 3 },
    { name: "syncthing", key: "", proc: "syncthing", own: true, down: 5000, up: 88000, conns: 11 },
    { name: "firefox", key: "", proc: "firefox", own: true, down: 6000, up: 2000, conns: 2 } ] })
  property var stats: ({ today: "2026-10-25", days: (function() {
    var out = [], G = 1073741824
    var plan = [[0.4, 0.1, 0.9], [2.1, 0.3, 1.2], [0.2, 0.0, 0.7], [5.6, 0.2, 1.4], [0.6, 3.8, 1.1], [1.2, 0.4, 0.8],
                [0.3, 0.2, 1.0], [7.9, 0.1, 1.6], [1.4, 4.2, 0.9], [0.5, 0.2, 1.3], [3.3, 0.6, 1.1], [0.8, 0.3, 0.6],
                [0.2, 0.1, 0.9], [4.4, 0.4, 1.2], [0.9, 6.1, 1.0], [0.4, 0.2, 0.8], [2.6, 0.2, 1.5], [0.3, 0.1, 0.7],
                [1.1, 0.5, 1.2], [6.2, 0.3, 0.9], [0.6, 2.4, 1.3], [0.2, 0.1, 1.1], [3.9, 0.4, 0.8], [0.7, 0.2, 1.0],
                [1.8, 5.3, 1.4], [0.3, 0.1, 0.9], [4.8, 0.2, 1.2], [0.5, 1.9, 0.8], [2.2, 0.3, 1.1], [3.1, 1.2, 1.3]]
    for (var i = 0; i < plan.length; i++) {
      var d = new Date(Date.UTC(2026, 9, 25 - (plan.length - 1 - i)))
      var p = plan[i]
      var apps = [ { name: "Steam", down: p[0] * G, up: 0.02 * G }, { name: "Heroic", down: p[1] * G, up: 0.01 * G },
                   { name: "Chrome", down: p[2] * G, up: 0.08 * G }, { name: "spotify", down: 0.12 * G, up: 0.01 * G },
                   { name: "qBittorrent", down: (i % 4 === 0 ? 1.4 : 0.1) * G, up: (i % 4 === 0 ? 2.2 : 0.2) * G } ]
      var rx = 0, tx = 0
      for (var j = 0; j < apps.length; j++) { rx += apps[j].down; tx += apps[j].up }
      out.push({ date: d.toISOString().slice(0, 10), rx: rx * 1.18, tx: tx * 1.25, apps: apps })
    }
    return out })() })
  property var history: (function() {
    var out = [], now = Date.now()
    for (var i = 0; i < 60; i++) {
      var steam = 1150000 + 60000 * Math.sin(i / 3) + (i > 35 ? 0 : -400000 * (1 - i / 35))
      var heroic = i < 12 ? 300000 + i * 70000 : 1235000 + 20000 * Math.sin(i / 2)
      var chrome = 160000 + 140000 * Math.max(0, Math.sin(i / 5))
      var spotify = 41000 + 15000 * Math.sin(i / 4)
      var other = 120000 + 60000 * Math.sin(i / 7 + 1)
      out.push({ t: now - (59 - i) * 1500, down: steam + heroic + chrome + spotify + 11000 + other, up: 96000,
        apps: { Steam: steam, Heroic: heroic, Chrome: chrome, spotify: spotify, syncthing: 5000, firefox: 6000 } })
    }
    return out })()
  property bool statsWanted: false
  property bool trafficWanted: false
  property bool limiting: !paused && !setup && error === "" && !noLimit
  property string installCommand: "sudo bash ~/.config/omarchy/plugins/yoyo.throttle/scripts/install.sh"
  property string uninstallCommand: "sudo bash ~/.config/omarchy/plugins/yoyo.throttle/scripts/uninstall.sh"
  function tick(f) {}
  function setEnabled(on) {}
  function toggleEnabled() {}
  function setPatch(p) {}
  function setApp(a, f, v) {}
  function setGlobal(f, v) {}
  function copyInstallCommand() {}
  function copyUninstallCommand() {}
  function resetStats() {}
  function addApp(p, l) { return true }
  function removeApp(k) {}
}
