// Sanity tests for Model.js outside QML:  node tests/model.test.js
const fs = require("fs"), path = require("path"), vm = require("vm")
const dir = path.join(__dirname, "..")
const ctx = { Defaults: {} }
vm.createContext(ctx)
vm.runInContext(fs.readFileSync(path.join(dir, "defaults.js"), "utf8") + "\nDefaults.CONFIG = CONFIG", ctx)
vm.runInContext(fs.readFileSync(path.join(dir, "Model.js"), "utf8").replace(/^\.(pragma|import).*$/gm, ""), ctx)
let pass = 0, fail = 0
function eq(label, got, want) {
  const g = JSON.stringify(got), w = JSON.stringify(want)
  if (g === w) { pass++; console.log("PASS  " + label) } else { fail++; console.log("FAIL  " + label + "\n      got " + g + " want " + w) }
}
const M = ctx
eq("rateKey preset", M.rateKey(25, false), "25")
eq("rateKey custom value", M.rateKey(30, false), "custom")
eq("rateKey custom open", M.rateKey(25, true), "custom")
eq("stepPreset up", M.stepPreset(0, 1), 10)
eq("stepPreset clamps", M.stepPreset(100, 1), 100)
eq("stepPreset from custom up", M.stepPreset(30, 1), 50)
eq("stepPreset from custom down", M.stepPreset(30, -1), 25)
eq("formatRate", [M.formatRate(0), M.formatRate(1250), M.formatRate(1250000), M.formatRate(125e6)], ["0", "10 kbit/s", "10.0 Mbit/s", "1000 Mbit/s"])
const cfg = M.merged(M.DEFAULTS, M.patchFor("heroic", "downMbit", 10))
eq("patch merges one app field", [cfg.apps.heroic.downMbit, cfg.apps.heroic.gamesSafe, cfg.apps.steam.downMbit], [10, true, 0])
eq("defaults untouched", M.DEFAULTS.apps.heroic.downMbit, 0)
eq("anyCap", [M.anyCap(M.DEFAULTS), M.anyCap(cfg)], [false, true])
const status = { helper: "installed", applied: true, mode: "apply", iface: "enp42s0", error: "",
  apps: [{ key: "heroic", running: true, cgroups: ["x"], refused: [], shared: ["ghostty"] }, { key: "steam", running: false, cgroups: [], refused: [], shared: [] }] }
eq("statusLine limiting", M.statusLine(status, cfg), "Limiting on enp42s0 · Heroic")
eq("isLimiting", M.isLimiting(status, cfg), true)
eq("paused", M.statusLine(status, M.merged(cfg, { enabled: false })), "Paused — nothing is limited")
eq("setup", M.statusLine({ helper: "missing" }, cfg), "One-time setup needed")
const rows = M.appRows(cfg, status)
eq("app rows shape", rows.map(r => r.kind), ["header", "rate", "rate", "toggle", "header", "rate", "rate", "toggle"])
eq("heroic header mentions shared cgroup", rows[0].subtitle, "Limited · also caps: ghostty")
eq("steam not running", rows[4].subtitle, "Not running")
eq("refused-only app explains why",
  M.appSubtitle({ apps: [{ key: "heroic", running: true, cgroups: [], refused: ["session-2.scope:outside-user-manager"], shared: [] }] }, cfg, "heroic"),
  "Can't limit: started outside an app scope (relaunch from the app menu)")
console.log("\npassed " + pass + ", failed " + fail)
process.exit(fail ? 1 : 0)
