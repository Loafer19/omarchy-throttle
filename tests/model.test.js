// Sanity tests for model/*.js outside QML:  node tests/model.test.js
const fs = require("fs"), path = require("path"), vm = require("vm")
const dir = path.join(__dirname, "..")
// Loads a QML JavaScript resource the way the engine does: every `.import
// "file.js" as Name` becomes its own (shared, .pragma library) module object.
const modules = {}
function load(file) {
  if (modules[file]) return modules[file]
  const ctx = modules[file] = vm.createContext({})
  const src = fs.readFileSync(file, "utf8")
  for (const m of src.matchAll(/^\.import "([^"]+)" as (\w+)/gm)) ctx[m[2]] = load(path.join(path.dirname(file), m[1]))
  vm.runInContext(src.replace(/^\.(pragma|import).*$/gm, ""), ctx, { filename: file })
  return ctx
}
// M: every module's names in one namespace (modules never redefine each
// other's names, they only alias them), so tests don't care where a helper lives.
const modelFiles = fs.readdirSync(path.join(dir, "model")).filter(f => f.endsWith(".js")).sort()
const M = Object.assign({}, ...modelFiles.map(f => load(path.join(dir, "model", f))))
let pass = 0, fail = 0
function eq(label, got, want) {
  const g = JSON.stringify(got), w = JSON.stringify(want)
  if (g === w) { pass++; console.log("PASS  " + label) } else { fail++; console.log("FAIL  " + label + "\n      got " + g + " want " + w) }
}
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
const rows = M.appListRows(cfg, status, null, true)
eq("apps list shape", rows.map(r => r.kind), ["app", "app", "section", "link"])
eq("heroic row mentions shared cgroup + games-safe", [rows[0].subtitle, rows[0].state, rows[0].down], ["Limited · also caps: ghostty · games-safe", "limited", 10])
eq("steam not running", [rows[1].subtitle, rows[1].state], ["Not running", "idle"])
eq("whole connection link", [rows[3].target, rows[3].subtitle], ["connection", "Every app on enp42s0 together"])
eq("live rate in app row", M.appListRows(cfg, status, { apps: [{ key: "heroic", name: "Heroic", down: 1235000, up: 0 }] }, true)[0].subtitle.split(" · ").slice(-1)[0], "↓ 9.9 Mbit/s now")
const det = M.detailRows(cfg, status, { apps: [{ key: "heroic", name: "Heroic", down: 1235000, up: 0 }] }, "heroic", true)
eq("detail shape", det.map(r => r.kind + ":" + (r.field || "")), ["crumb:", "hero:", "rate:downMbit", "rate:upMbit", "toggle:gamesSafe"])
eq("detail hero", [det[1].removable, det[1].trailing, det[1].subtitle], [false, "↓ 9.9 / 10 Mbit/s", "Limited · also caps: ghostty · heroic, legendary, gogdl, nile"])
eq("preset hero is not selectable, removable hero is", [M.selectableRow(det[1]), M.selectableRow({ kind: "hero", removable: true }), M.selectableRow(det[0])], [false, true, true])
eq("detail of unknown app", M.detailRows(cfg, status, null, "nope"), [])
eq("connection rows", M.connectionRows(cfg, status).map(r => r.kind), ["rate", "rate", "note"])
eq("subtabs", [M.subtabsOf("limits").map(t => t.key), M.subtabsOf("traffic").length, M.subtabsOf("settings")], [["apps", "connection", "add"], 4, []])
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
const det2 = M.detailRows(cfg2, status, traffic, "qbittorrent", true)
eq("custom hero removable + procs in subtitle", [det2[1].removable, det2[1].subtitle], [true, "Not running · applies when it starts · qbittorrent"])
eq("custom games-safe off wording", det2[4].subtitle, "Everything Qbittorrent and its children send is capped")
eq("add rows skip added app", M.addRows(cfg2, traffic).map(r => r.kind + ":" + (r.proc || "")), ["section:", "candidate:chrome", "section:", "addfield:"])
eq("add rows with nothing new", M.addRows(cfg2, { apps: [] }).map(r => r.kind), ["section", "note", "section", "addfield"])
eq("statusLine uses custom label", M.statusLine(status, cfg2), "Limiting on enp42s0 · Heroic · Qbittorrent")
eq("labelCapped", [M.labelCapped(cfg2, "Qbittorrent"), M.labelCapped(cfg2, "Steam")], [true, false])
eq("removePatch presets refused", [M.removePatch(cfg2, "steam"), M.removePatch(cfg2, "qbittorrent")], [null, { apps: { qbittorrent: null } }])
eq("null patch removes app from cfg", Object.keys(M.merged(cfg2, M.removePatch(cfg2, "qbittorrent")).apps), ["heroic", "steam"])
eq("keepNulls keeps the instruction", M.merged({}, { apps: { x: null } }, true), { apps: { x: null } })
let full = cfg2
for (const n of ["a1", "a2", "a3", "a4", "a5"]) full = M.merged(full, M.addPatch(full, n))
eq("max apps", [M.appList(full).length, M.canAdd(full), M.addPatch(full, "a6")], [8, false, null])
eq("full list: add view is an empty state", M.addRows(full, traffic).map(r => r.kind), ["empty"])

const tg = M.addPatch(cfg, "telegram-deskto", "telegram-desktop")
eq("long name: matched by 15-char comm, full label/key", [Object.keys(tg.apps)[0], tg.apps["telegram-deskto"] ? "" : Object.values(tg.apps)[0].label, Object.values(tg.apps)[0].procs],
  ["telegram-deskt", "Telegram-desktop", ["telegram-deskto"]])
eq("typed long name is cut to the comm", M.addPatch(cfg, "telegram-desktop").apps["telegram-deskt"].procs, ["telegram-deskto"])
eq("validName", [M.validName("telegram-desktop"), M.validName("x".repeat(33)), M.validName("bash"), M.validName("a/b")], [true, false, false, false])
eq("candidate carries full name", M.addRows(cfg, { apps: [{ name: "telegram-deskto", key: "", proc: "telegram-deskto", full: "telegram-desktop", own: true, down: 1, up: 1, conns: 1 }] })
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
const hr = M.historyRows(cfg, today, true)
eq("historyRows", hr.map(r => r.kind), ["total", "daychart", "section", "stat", "stat", "stat"])
eq("history rows carry key + caps", [hr[3].key, hr[3].capDown, hr[5].other, hr[0].caption], ["steam", 0, true, "peak 2 KiB/day"])
eq("history empty states", [M.historyRows(cfg, M.statsSummary(null, "week"), false).slice(-1)[0].title, M.historyRows(cfg, M.statsSummary(null, "week"), true).slice(-1)[0].title],
  ["Loading…", "Nothing counted in this range yet"])
eq("empty stats", M.statsSummary(null, "week").apps, [])

// ---- steps / units ----
eq("stepsOf default + custom", [M.stepsOf(M.DEFAULTS), M.stepsOf({ steps: [50, 5, 5, 20, 10] }), M.stepsOf({ steps: [] })], [[0, 10, 25, 50, 100], [0, 5, 10, 20, 50], [0, 10, 25, 50, 100]])
const s5 = M.stepsOf({ steps: [5, 10, 20, 50] })
eq("rateKey/stepPreset with steps", [M.rateKey(20, false, s5), M.rateKey(25, false, s5), M.stepPreset(0, 1, s5), M.stepPreset(30, 1, s5)], ["20", "custom", 5, 50])
eq("rateChips", M.rateChips(s5).map(c => c.label), ["Off", "5", "10", "20", "50", "Custom"])
eq("capDetail", [M.capDetail(0), M.capDetail(10), M.capDetail(100)], ["Off · no cap", "10 Mbit/s ≈ 1.3 MB/s", "100 Mbit/s ≈ 13 MB/s"])
eq("formatRate mbyte", [M.formatRate(500, "mbyte"), M.formatRate(85000, "mbyte"), M.formatRate(1250000, "mbyte"), M.formatRate(125e6, "mbyte")], ["0", "85 kB/s", "1.3 MB/s", "125 MB/s"])
eq("shortRate", [M.shortRate(100), M.shortRate(106250), M.shortRate(1235000), M.shortRate(2410000), M.shortRate(1235000, "mbyte")], ["0", "850k", "9.9M", "19M", "1.2MB"])

// ---- settings ----
const sr = M.settingsRows(cfg, status, true)
eq("settings shape", sr.map(r => r.kind === "section" ? "#" + r.title : r.setting || r.action),
  ["#Display", "units", "barWidget", "#Limits", "steps", "bulkMiB", "#History", "keepDays", "clear-history", "#Helper", "copy-uninstall"])
eq("settings values", [sr[1].value, sr[2].value, sr[4].value, sr[5].value, sr[7].value], ["mbit", "icon", "10,25,50,100", "4", "35"])
eq("helper missing → copy install", M.settingsRows(cfg, { helper: "missing" }, false).slice(-1)[0].action, "copy-install")
eq("odd steps/keepDays get their own chip", [M.settingsRows({ steps: [1, 2], keepDays: 12, apps: {} }, null, true)[4].options.slice(-1)[0].label,
  M.settingsRows({ keepDays: 12, apps: {} }, null, true)[7].options.slice(-1)[0].label], ["1/2", "12 days"])
eq("settingPatch", [M.settingPatch(cfg, "units", "mbyte"), M.settingPatch(cfg, "steps", "5,10,20,50"), M.settingPatch(cfg, "keepDays", "90"), M.settingPatch(cfg, "nope", "x")],
  [{ units: "mbyte" }, { steps: [5, 10, 20, 50] }, { keepDays: 90 }, null])
eq("bulkMiB goes to every app", M.settingPatch(cfg2, "bulkMiB", "16"), { apps: { heroic: { bulkMiB: 16 }, steam: { bulkMiB: 16 }, qbittorrent: { bulkMiB: 16 } } })
eq("stepChoice", [M.stepChoice(sr[2], 1, false), M.stepChoice(sr[2], -1, false), M.stepChoice(sr[2], -1, true), M.stepChoice({ options: sr[2].options, value: "rate" }, 1, true)], ["dot", "icon", "rate", "icon"])

// ---- live chart ----
const tr = (d, apps) => ({ iface: { down: d, up: 1 }, apps: apps })
let h = []
for (let i = 0; i < 5; i++) h = M.pushSample(h, tr(1000 + i, [{ name: "Steam", down: 600 }, { name: "Heroic", down: 200 }, { name: "Heroic", down: 100 }]), 1500 * i)
eq("pushSample appends + sums same name", [h.length, h[4].apps, h[4].down], [5, { Steam: 600, Heroic: 300 }, 1004])
eq("pushSample caps the window", M.pushSample(h, tr(1, []), 7500, 3).length, 3)
eq("pushSample gap starts fresh", M.pushSample(h, tr(1, []), 60000).length, 1)
eq("pushSample ignores missing traffic", M.pushSample(h, null, 7500).length, 5)
const ls = M.liveSeries(h, 1)
eq("liveSeries top-n + other", [ls.names, ls.layers[0][0], ls.other[0], ls.total[4], ls.span, ls.count], [["Steam"], 600, 400, 1004, 6, 5])
eq("liveSeries axis in display units", [M.liveSeries([{ t: 0, down: 2.9e6, apps: {} }]).max, M.liveSeries([{ t: 0, down: 2.9e6, apps: {} }], 4, "mbyte").max], [25e6 / 8, 5e6])
eq("paused rows don't say Limited", M.appListRows(M.merged(cfg, { enabled: false }), status, null, false)[0].subtitle, "Paused · also caps: ghostty · games-safe")
eq("liveSeries empty", [M.liveSeries([]).count, M.liveSeries(null).peak], [0, 0])
eq("niceCeil", [M.niceCeil(0), M.niceCeil(0.7), M.niceCeil(1.5), M.niceCeil(2.2), M.niceCeil(3), M.niceCeil(23.5), M.niceCeil(100)], [1, 1, 2, 2.5, 5, 25, 100])
eq("liveRows", M.liveRows(cfg, { iface: { down: 5, up: 1 }, apps: traffic.apps }, h).map(r => r.kind).slice(0, 4), ["total", "livechart", "section", "traffic"])
eq("live rows: addable + caps", M.liveRows(cfg, { iface: { down: 5, up: 1 }, apps: traffic.apps }, h).slice(3).map(r => [r.name, r.capDown, r.addable]),
  [["Steam", 0, false], ["chrome", 0, true], ["bash", 0, false], ["tailscaled", 0, false], ["qbittorrent", 0, true]])
eq("live empty / measuring", [M.liveRows(cfg, null, []).slice(-1)[0].title, M.liveRows(cfg, { iface: { down: 0, up: 0 }, apps: [] }, []).slice(-1)[0].title],
  ["Measuring…", "No open TCP connections"])

// ---- bar widget ----
const heroicAt = d => ({ iface: { down: d, up: 0 }, apps: [{ key: "heroic", name: "Heroic", down: d, up: 0 }] })
eq("biting at 90 % of the cap", [M.biting(cfg, heroicAt(1200000)), M.biting(cfg, heroicAt(1000000)), M.biting(M.DEFAULTS, heroicAt(9e9))], [true, false, false])
eq("tooltip", M.tooltipText(cfg, status, heroicAt(1235000), true).split("\n"), ["Throttle on · enp42s0", "Heroic  ↓ 9.9 Mbit/s / 10 Mbit/s", "Right-click to pause"])
eq("tooltip states", [M.tooltipText(cfg, null), M.tooltipText(cfg, { helper: "missing" }), M.tooltipText(M.merged(cfg, { enabled: false }), status), M.tooltipText(M.DEFAULTS, status)],
  ["Throttle", "Throttle · one-time setup needed", "Throttle paused · right-click to resume", "Throttle · no limits"])
let many = M.DEFAULTS
for (const n of ["aa", "bb", "cc"]) { many = M.merged(many, M.addPatch(many, n)); many = M.merged(many, M.patchFor(n, "downMbit", 5)) }
many = M.merged(many, M.patchFor("heroic", "downMbit", 5))
const manyStatus = { helper: "installed", applied: true, mode: "apply", iface: "eth0", error: "", apps: ["heroic", "aa", "bb", "cc"].map(k => ({ key: k, running: true, cgroups: ["x"], refused: [], shared: [] })) }
eq("statusLine shows 3 names then +N", M.statusLine(manyStatus, many), "Limiting on eth0 · Heroic · Aa · +2 apps")

// model/*.js helpers behind the facade
eq("findApp by key / label / miss", [M.findApp(M.DEFAULTS, "key", "steam").label, M.findApp(M.DEFAULTS, "label", "Heroic").key, M.findApp(M.DEFAULTS, "key", "nope")], ["Steam", "heroic", null])
eq("keyOfLabel / labelCapped", [M.keyOfLabel(cfg, "Heroic"), M.keyOfLabel(cfg, "Nope"), M.labelCapped(cfg, "Heroic"), M.labelCapped(cfg, "Steam")], ["heroic", "", true, false])
eq("formatAmount bytes vs rate", [M.formatAmount(2048, true, "mbit"), M.formatAmount(1250, false, "mbit")], ["2 KiB", "10 kbit/s"])
eq("anyCap: whole connection only", M.anyCap(M.merged(M.DEFAULTS, { upMbit: 5 })), true)
const keepRow = M.settingsRows(M.merged(M.DEFAULTS, { keepDays: 10 }), null, true).find(r => r.setting === "keepDays")
eq("keep choices: unit on the last, odd value appended", keepRow.options.map(o => o.label), ["7", "35", "90 days", "10 days"])
eq("every model module loads", modelFiles.length, 9)

// model/nav.js: the panel's keyboard cursor
const navRows = [{ kind: "section" }, { kind: "app" }, { kind: "note" }, { kind: "app" }]
eq("first / next selectable skip headers", [M.firstSelectable(navRows), M.nextSelectable(navRows, 1, 1), M.nextSelectable(navRows, 3, 1), M.nextSelectable(navRows, 1, -1)], [1, 3, -1, -1])
eq("chipIndex by key, 0 when missing", [M.chipIndex(M.TABS, "settings"), M.chipIndex(M.TABS, "nope")], [2, 0])
eq("cycleIndex wraps both ways", [M.cycleIndex(2, 1, 3), M.cycleIndex(0, -1, 3)], [0, 2])
eq("clampIndex", [M.clampIndex(-1, 3), M.clampIndex(5, 3)], [0, 2])
eq("j from tabs: filters, else first row", [M.verticalTarget("tabs", 0, navRows, true, 1), M.verticalTarget("tabs", 0, navRows, false, 1), M.verticalTarget("tabs", 0, navRows, true, -1)], [{ section: "filters" }, { section: "rows", index: 1 }, null])
eq("k from filters: tabs", M.verticalTarget("filters", 1, navRows, true, -1), { section: "tabs" })
eq("rows: next, then back up to the chips", [M.verticalTarget("rows", 1, navRows, true, 1), M.verticalTarget("rows", 1, navRows, true, -1), M.verticalTarget("rows", 3, navRows, false, 1)], [{ section: "rows", index: 3 }, { section: "filters", top: true }, null])
eq("keyHints: detail page", M.keyHints({ inDetail: true, tab: "limits" }).map(h => h[1]), ["back", "rows", "change", "toggle", "pause"])
eq("keyHints: filters cursor on Traffic", M.keyHints({ section: "filters", cursorActive: true, tab: "traffic" })[0], ["h l", "range"])
eq("keyHints: + Add", M.keyHints({ tab: "limits", limitsSub: "add" }).map(h => h[1]), ["tabs", "rows", "add", "pause"])
eq("subCaption", [M.subCaption("limits", "live", M.DEFAULTS, null), M.subCaption("traffic", "live", M.DEFAULTS, { iface: "eth0" }), M.subCaption("traffic", "week", M.DEFAULTS, null)], ["2 of 8 apps", "eth0 · every 1.5 s", "network"])
eq("rowsFor picks the view", [M.rowsFor({ tab: "limits", limitsSub: "connection", cfg: M.DEFAULTS, status: null }).length > 0, M.rowsFor({ tab: "settings", cfg: M.DEFAULTS, status: null, needsSetup: false })[0].kind], [true, M.settingsRows(M.DEFAULTS, null, true)[0].kind])
eq("peakOf: at least 1", [M.peakOf({ apps: [] }), M.peakOf({ apps: [{ down: 3, up: 4 }, { down: 1, up: 0 }] })], [1, 7])

console.log("\npassed " + pass + ", failed " + fail)
process.exit(fail ? 1 : 0)
