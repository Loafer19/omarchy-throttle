import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Always loaded (keepLoaded): re-applies limits at login, when the network
// interface changes, and when a limited app starts or restarts (its cgroup is
// what the kernel rule matches, so a new cgroup means a new rule). Also keeps
// the traffic history for the Stats tab (one unprivileged `ss` read per 10 s).
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

  property var cfg: Model.DEFAULTS
  property var status: null
  property var traffic: null
  property bool loaded: false
  // The panel flips this while it shows the Traffic tab; sampling ss is
  // cheap but there is no reason to do it with the panel closed.
  property bool trafficWanted: false
  // Per-day history ({ today, days: [...] }); refreshed while the Stats tab is open.
  property var stats: null
  property bool statsWanted: false

  readonly property bool limiting: Model.isLimiting(status, cfg)
  readonly property string script:
    Qt.resolvedUrl("scripts/backend.sh").toString().replace(/^file:\/\//, "")
  readonly property string installScript:
    Qt.resolvedUrl("scripts/install.sh").toString().replace(/^file:\/\//, "")
  readonly property string installCommand: "sudo bash " + (/^[A-Za-z0-9_.\/@+-]+$/.test(installScript)
    ? installScript : "'" + installScript.replace(/'/g, "'\\''") + "'")

  signal settingsChanged()

  function backend(args) { return ["bash", root.script].concat(args) }

  function setPatch(patch) {
    root.cfg = Model.merged(root.cfg, patch)
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
    for (var i = 0; i < pendingPatches.length; i++) merged = Model.merged(merged, pendingPatches[i], true)
    pendingPatches = []
    setProc.command = root.backend(["settings-set", JSON.stringify(merged)])
    setProc.running = true
  }

  function setEnabled(on) { root.setPatch({ enabled: on === true }) }
  function toggleEnabled() { root.setEnabled(!(root.cfg && root.cfg.enabled !== false)) }
  function setGlobal(field, mbit) { root.setPatch(Model.patchFor("", field, Model.clampMbit(mbit))) }
  function setApp(app, field, value) { root.setPatch(Model.patchFor(app, field, value)) }
  function addApp(proc) {
    var p = Model.addPatch(root.cfg, proc)
    if (p) root.setPatch(p)
    return p !== null
  }
  function removeApp(key) {
    var p = Model.removePatch(root.cfg, key)
    if (p) root.setPatch(p)
  }

  function sampleStats() {
    if (statsProc.running) return
    statsProc.command = root.backend(root.statsWanted ? ["stats-sample", "--print"] : ["stats-sample"])
    statsProc.running = true
  }
  onStatsWantedChanged: if (statsWanted) sampleStats()

  function tick(force) {
    if (tickProc.running) {
      if (force) tickAgain.restart()
      return
    }
    tickProc.command = root.backend(force ? ["tick", "--force"] : ["tick"])
    tickProc.running = true
  }

  function sampleTraffic() {
    if (trafficProc.running) return
    trafficProc.command = root.backend(["traffic"])
    trafficProc.running = true
  }

  function copyInstallCommand() {
    Quickshell.execDetached(["wl-copy", root.installCommand])
  }

  Process {
    id: getProc
    command: root.backend(["settings-get"])
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          if (data && typeof data === "object") {
            root.cfg = data
            root.loaded = true
            root.settingsChanged()
          }
        } catch (e) {}
        root.tick(false)
      }
    }
  }

  Process {
    id: setProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          if (data && typeof data === "object" && !data.error && root.pendingPatches.length === 0) {
            root.cfg = data
            root.settingsChanged()
          }
        } catch (e) {}
      }
    }
    onExited: {
      if (root.pendingPatches.length > 0) root.flushPatches()
      else tickSoon.restart()
    }
  }

  Process {
    id: tickProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          if (data && typeof data === "object") root.status = data
        } catch (e) {}
      }
    }
  }

  Process {
    id: trafficProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          if (data && Array.isArray(data.apps)) root.traffic = data
        } catch (e) {}
      }
    }
  }

  Process {
    id: statsProc
    stdout: StdioCollector {
      onStreamFinished: {
        if (!root.statsWanted) return
        try {
          var data = JSON.parse(text)
          if (data && Array.isArray(data.days)) root.stats = data
        } catch (e) {}
      }
    }
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
    interval: 1500
    running: root.trafficWanted
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

  Component.onCompleted: getProc.running = true
  // Shell reload / logout: write the in-memory (tmpfs) day totals to disk.
  Component.onDestruction: Quickshell.execDetached(root.backend(["stats-sample", "--sync"]))
}
