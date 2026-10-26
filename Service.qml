import QtQuick
import Quickshell
import Quickshell.Io
import "defaults.js" as Defaults
import "model/format.js" as Format
import "model/apps.js" as Apps
import "model/live.js" as Live
import "model/status.js" as Status
import "components" as Throttle

// Always loaded (keepLoaded): re-applies limits at login, when the network
// interface changes, and when a limited app starts or restarts (its cgroup is
// what the kernel rule matches, so a new cgroup means a new rule). Also keeps
// the traffic history for Traffic › Today / 7 / 30 days (one unprivileged
// `ss` read per 10 s).
Item {
  id: root
  width: 0
  height: 0
  visible: false

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null
  property string omarchyPath: ""

  property var cfg: Defaults.CONFIG
  property var status: null
  property var traffic: null
  property bool loaded: false
  // The panel flips this while it shows live rates; sampling ss is cheap but
  // there is no reason to do it with the panel closed — unless the bar widget
  // shows a rate or a "cap is maxed out" dot (Settings › Bar widget).
  property bool trafficWanted: false
  readonly property string widgetMode: cfg && (cfg.barWidget === "dot" || cfg.barWidget === "rate") ? cfg.barWidget : "icon"
  readonly property bool widgetWantsTraffic: widgetMode === "rate" || (widgetMode === "dot" && limiting)
  // Traffic › Live: the last 90 s of samples (Live.pushSample).
  property var history: []
  // Per-day history ({ today, days: [...] }); refreshed while the Stats tab is open.
  property var stats: null
  property bool statsWanted: false

  readonly property bool limiting: Status.isLimiting(status, cfg)
  function localPath(rel) { return Qt.resolvedUrl(rel).toString().replace(/^file:\/\//, "") }
  readonly property string script: localPath("scripts/backend.sh")
  readonly property string installScript: localPath("scripts/install.sh")
  readonly property string uninstallScript: localPath("scripts/uninstall.sh")
  function shellQuote(p) { return /^[A-Za-z0-9_.\/@+-]+$/.test(p) ? p : "'" + p.replace(/'/g, "'\\''") + "'" }
  readonly property string installCommand: "sudo bash " + shellQuote(installScript)
  readonly property string uninstallCommand: "sudo bash " + shellQuote(uninstallScript)

  signal settingsChanged()

  function backend(args) { return ["bash", root.script].concat(args) }

  function setPatch(patch) {
    root.cfg = Apps.merged(root.cfg, patch)
    root.settingsChanged()
    pendingPatches.push(patch)
    flushPatches()
  }

  // Writes are serialized so two quick clicks can't race each other's file write.
  property var pendingPatches: []
  function flushPatches() {
    if (setProc.running || pendingPatches.length === 0) return
    var merged = {}
    // keepNulls: { apps: { key: null } } is how an app gets removed.
    for (var i = 0; i < pendingPatches.length; i++) merged = Apps.merged(merged, pendingPatches[i], true)
    pendingPatches = []
    setProc.run(["settings-set", JSON.stringify(merged)])
  }

  function setEnabled(on) { root.setPatch({ enabled: on === true }) }
  function toggleEnabled() { root.setEnabled(!(root.cfg && root.cfg.enabled !== false)) }
  function setGlobal(field, mbit) { root.setPatch(Apps.patchFor("", field, Format.clampMbit(mbit))) }
  function setApp(app, field, value) { root.setPatch(Apps.patchFor(app, field, value)) }
  function addApp(proc, label) {
    var p = Apps.addPatch(root.cfg, proc, label)
    if (p) root.setPatch(p)
    return p !== null
  }
  function removeApp(key) {
    var p = Apps.removePatch(root.cfg, key)
    if (p) root.setPatch(p)
  }

  function sampleStats() { statsProc.run(root.statsWanted ? ["stats-sample", "--print"] : ["stats-sample"]) }
  onStatsWantedChanged: if (statsWanted) sampleStats()

  function tick(force) {
    if (!tickProc.run(force ? ["tick", "--force"] : ["tick"]) && force) tickAgain.restart()
  }

  function sampleTraffic() { trafficProc.run(["traffic"]) }

  function copyInstallCommand() {
    Quickshell.execDetached(["wl-copy", root.installCommand])
  }
  function copyUninstallCommand() {
    Quickshell.execDetached(["wl-copy", root.uninstallCommand])
  }

  // Settings › Clear history.
  function resetStats() { resetProc.run(["stats-reset"]) }

  Throttle.BackendCall {
    id: getProc
    script: root.script
    onReceived: {
      const data = getProc.data
      if (data) {
        root.cfg = data
        root.loaded = true
        root.settingsChanged()
      }
      root.tick(false)
    }
  }

  Throttle.BackendCall {
    id: setProc
    script: root.script
    onReceived: {
      const data = setProc.data
      if (data && !data.error && root.pendingPatches.length === 0) {
        root.cfg = data
        root.settingsChanged()
      }
    }
    onExited: {
      if (root.pendingPatches.length > 0) root.flushPatches()
      else tickSoon.restart()
    }
  }

  Throttle.BackendCall {
    id: tickProc
    script: root.script
    onReceived: if (tickProc.data) root.status = tickProc.data
  }

  Throttle.BackendCall {
    id: trafficProc
    script: root.script
    onReceived: {
      const data = trafficProc.data
      if (data && Array.isArray(data.apps)) {
        root.traffic = data
        root.history = Live.pushSample(root.history, data, Date.now(), Live.LIVE_SAMPLES)
      }
    }
  }

  Throttle.BackendCall {
    id: resetProc
    script: root.script
    onExited: {
      root.stats = null
      root.sampleStats()
    }
  }

  Throttle.BackendCall {
    id: statsProc
    script: root.script
    onReceived: if (root.statsWanted && statsProc.data && Array.isArray(statsProc.data.days)) root.stats = statsProc.data
  }

  // Settings changes apply quickly; the 5 s poll catches app (re)starts,
  // interface changes and shaping that vanished (suspend/resume, reboot).
  Timer { id: tickSoon; interval: 250; onTriggered: root.tick(false) }
  Timer { id: tickAgain; interval: 600; onTriggered: root.tick(true) }
  Timer {
    interval: 5000
    running: root.loaded
    repeat: true
    onTriggered: root.tick(false)
  }
  Timer {
    interval: root.trafficWanted ? 1500 : 3000
    running: root.trafficWanted || root.widgetWantsTraffic
    repeat: true
    triggeredOnStart: true
    onTriggered: root.sampleTraffic()
  }

  Timer {
    interval: root.statsWanted ? 3000 : 10000
    running: root.loaded
    repeat: true
    onTriggered: root.sampleStats()
  }

  // The plugin's one IPC target (`qs ipc call yoyo.throttle toggle`). Here,
  // not in BarWidget.qml: the bar builds a widget per monitor, and every extra
  // handler for the target is "registered but will not be used". Panel calls go
  // through the shell, which opens the bar's panel on the focused monitor (as
  // `omarchy-shell shell toggle yoyo.throttle` does).
  readonly property string pluginId: "yoyo.throttle"
  function host() {
    var s = root.shell
    return s && typeof s.summon === "function" && typeof s.hide === "function"
      && typeof s.toggle === "function" ? s : null
  }

  IpcHandler {
    target: "yoyo.throttle"

    function open(): void { var s = root.host(); if (s) s.summon(root.pluginId, "") }
    function close(): void { var s = root.host(); if (s) s.hide(root.pluginId) }
    function toggle(): void { var s = root.host(); if (s) s.toggle(root.pluginId, "") }
    function pause(): void { root.setEnabled(false) }
    function resume(): void { root.setEnabled(true) }
  }

  Component.onCompleted: getProc.run(["settings-get"])
  // Shell reload / logout: write the in-memory (tmpfs) day totals to disk.
  Component.onDestruction: Quickshell.execDetached(root.backend(["stats-sample", "--sync"]))
}
