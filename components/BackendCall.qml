import QtQuick
import Quickshell.Io

// One scripts/backend.sh subcommand at a time: run(args) starts it unless the
// previous run is still going. When it finishes, `data` holds the JSON object
// it printed (null when the output was empty or not an object) and
// received() fires. (`data` is a property rather than a signal argument: a
// var argument would turn the object into a QVariantMap, arrays included.)
Process {
  id: call

  property string script: ""
  property var data: null
  signal received()

  function run(args) {
    if (call.running) return false
    call.command = ["bash", call.script].concat(args)
    call.running = true
    return true
  }

  stdout: StdioCollector {
    onStreamFinished: {
      let parsed = null
      try { parsed = JSON.parse(text) } catch (e) {}
      call.data = parsed && typeof parsed === "object" ? parsed : null
      call.received()
    }
  }
}
