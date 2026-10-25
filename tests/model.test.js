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
eq("app rows shape", rows.map(r => r.kind), ["header", "rate", "rate", "toggle", "header", "rate", "rate", "toggle", "section", "addfield"])
eq("presets are not removable", [rows[0].removable, rows[4].removable], [false, false])
eq("heroic header mentions shared cgroup", rows[0].subtitle, "Limited · also caps: ghostty")
eq("steam not running", rows[4].subtitle, "Not running")
eq("refused-only app explains why",
  M.appSubtitle({ apps: [{ key: "heroic", running: true, cgroups: [], refused: ["session-2.scope:outside-user-manager"], shared: [] }] }, cfg, "heroic"),
  "Can't limit: started outside an app scope (relaunch from the app menu)")

// ---- any app ----
const traffic = { apps: [
  { name: "Steam", key: "steam", proc: "steamwebhelper", own: true, down: 9, up: 1, conns: 2 },
  { name: "chrome", key: "", proc: "chrome", own: true, down: 500, up: 20, conns: 9 },
  { name: "bash", key: "", proc: "bash", own: true, down: 5, up: 1, conns: 1 },
  { name: "tailscaled", key: "", proc: "tailscaled", own: false, down: 50, up: 5, conns: 1 },
  { name: "qbittorrent", key: "", proc: "qbittorrent", own: true, down: 300, up: 900, conns: 40 }] }
eq("candidates: own, not denied, not known", M.candidates(traffic, cfg).map(c => c.proc), ["chrome", "qbittorrent"])
eq("validProc", [M.validProc("chrome"), M.validProc("bash"), M.validProc("a/b"), M.validProc("x".repeat(16)), M.validProc("Web Content")], [true, false, false, false, true])
eq("slugKey", [M.slugKey("Google Chrome", cfg), M.slugKey("9torrent", cfg), M.slugKey("steam", cfg), M.slugKey("..", cfg)], ["google-chrome", "torrent", "steam-2", "app"])
const add = M.addPatch(cfg, "qbittorrent")
eq("addPatch", add, { apps: { qbittorrent: { label: "Qbittorrent", procs: ["qbittorrent"], downMbit: 0, upMbit: 0, gamesSafe: false, bulkMiB: 4, preset: false } } })
eq("addPatch refuses known / denied / junk", [M.addPatch(cfg, "steam"), M.addPatch(cfg, "sudo"), M.addPatch(cfg, "a;b")], [null, null, null])
let cfg2 = M.merged(cfg, add)
cfg2 = M.merged(cfg2, M.patchFor("qbittorrent", "upMbit", 5))
eq("custom app listed after presets", M.appList(cfg2).map(a => a.key + ":" + a.preset), ["heroic:true", "steam:true", "qbittorrent:false"])
const rows2 = M.appRows(cfg2, status, traffic)
eq("custom header removable + procs in subtitle", [rows2[8].kind, rows2[8].removable, rows2[8].subtitle], ["header", true, "Not running · applies when it starts · qbittorrent"])
eq("custom toggle wording", rows2[11].title, "Big transfers only")
eq("candidate rows skip added app", rows2.filter(r => r.kind === "candidate").map(r => r.proc), ["chrome"])
eq("statusLine uses custom label", M.statusLine(status, cfg2), "Limiting on enp42s0 · Heroic · Qbittorrent")
eq("labelCapped", [M.labelCapped(cfg2, "Qbittorrent"), M.labelCapped(cfg2, "Steam")], [true, false])
eq("removePatch presets refused", [M.removePatch(cfg2, "steam"), M.removePatch(cfg2, "qbittorrent")], [null, { apps: { qbittorrent: null } }])
eq("null patch removes app from cfg", Object.keys(M.merged(cfg2, M.removePatch(cfg2, "qbittorrent")).apps), ["heroic", "steam"])
eq("keepNulls keeps the instruction", M.merged({}, { apps: { x: null } }, true), { apps: { x: null } })
let full = cfg2
for (const n of ["a1", "a2", "a3", "a4", "a5"]) full = M.merged(full, M.addPatch(full, n))
eq("max apps", [M.appList(full).length, M.canAdd(full), M.addPatch(full, "a6")], [8, false, null])
eq("full list shows note instead of add rows", M.appRows(full, status, traffic).slice(-1)[0].kind, "note")

const tg = M.addPatch(cfg, "telegram-deskto", "telegram-desktop")
eq("long name: matched by 15-char comm, full label/key", [Object.keys(tg.apps)[0], tg.apps["telegram-deskto"] ? "" : Object.values(tg.apps)[0].label, Object.values(tg.apps)[0].procs],
  ["telegram-deskt", "Telegram-desktop", ["telegram-deskto"]])
eq("typed long name is cut to the comm", M.addPatch(cfg, "telegram-desktop").apps["telegram-deskt"].procs, ["telegram-deskto"])
eq("validName", [M.validName("telegram-desktop"), M.validName("x".repeat(33)), M.validName("bash"), M.validName("a/b")], [true, false, false, false])
eq("candidate carries full name", M.appRows(cfg, status, { apps: [{ name: "telegram-deskto", key: "", proc: "telegram-deskto", full: "telegram-desktop", own: true, down: 1, up: 1, conns: 1 }] })
  .filter(r => r.kind === "candidate").map(r => [r.proc, r.title]), [["telegram-deskto", "telegram-desktop"]])

// ---- stats ----
eq("formatBytes", [M.formatBytes(0), M.formatBytes(2048), M.formatBytes(5 * 1048576), M.formatBytes(3 * 1073741824)], ["0 B", "2 KiB", "5.0 MiB", "3.00 GiB"])
eq("shiftDate across months", [M.shiftDate("2026-03-01", -1), M.shiftDate("2026-12-31", 1)], ["2026-02-28", "2027-01-01"])
const stats = { today: "2026-10-25", days: [
  { date: "2026-10-10", rx: 1000, tx: 100, apps: [{ name: "Steam", down: 800, up: 10 }] },
  { date: "2026-10-20", rx: 500, tx: 50, apps: [{ name: "Chrome", down: 300, up: 30 }] },
  { date: "2026-10-25", rx: 2000, tx: 200, apps: [{ name: "Steam", down: 1500, up: 20 }, { name: "Chrome", down: 100, up: 10 }] }] }
const today = M.statsSummary(stats, "today")
eq("today totals", today.total, { down: 2000, up: 200 })
eq("today rows + other", today.apps.map(a => [a.name, a.down, a.up]), [["Steam", 1500, 20], ["Chrome", 100, 10], ["Other / UDP", 400, 170]])
eq("today chart = 7 bars, only today in range", [today.bars.length, today.bars.filter(b => b.inRange).length, today.bars[6].today], [7, 1, true])
const week = M.statsSummary(stats, "week")
eq("week sums days in range", [week.total, week.apps[1]], [{ down: 2500, up: 250 }, { name: "Chrome", down: 400, up: 40 }])
const month = M.statsSummary(stats, "month")
eq("month", [month.total.down, month.bars.length, month.peak], [3500, 30, 2200])
eq("statsRows", M.statsRows(today).map(r => r.kind), ["range", "chart", "stat", "stat", "stat"])
eq("empty stats", M.statsSummary(null, "week").apps, [])

console.log("\npassed " + pass + ", failed " + fail)
process.exit(fail ? 1 : 0)
