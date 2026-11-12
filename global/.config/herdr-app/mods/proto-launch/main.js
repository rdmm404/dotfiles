// PROTOTYPE, throw away: the herdr-launch replacement, three layouts over the
// same real data. F1 Spotlight (list + side panel), F2 Columns (place, branch,
// start), F3 Inbox (running agents, sessions to pick up, places). Dry run by
// default: Enter shows the command it would run; F5 makes launches real.
// Tab cycles the agent (remembered per folder), Shift+Enter is a shell,
// Ctrl+Enter jumps to an open space. Local only: no machines, no GitHub, no
// worktree creation.

import { View, div, svg, image } from "gpui-kit";
import { v_flex, h_flex, InputState, Input, ScrollHandle } from "gpui-base";
import { spaces, panes, agents, knownAgents, exec, home, readTextFile, run, theme, props, closeOverlay } from "herdr";

const R = 1;
const LINE = 1;
const S1 = 5;
const S2 = 10;
const S3 = 15;
const HAIR = 2;
const TEXT = 13;
const SMALL = 11;

const HOME = home();
const MOD = `${HOME}/.config/herdr-app/mods/proto-launch`;
const HEIGHT = 520; // mod.json overlay height
// The agents Tab cycles through come from agents.json next to this file, in
// its order (the first is the default). An entry is a Herdr program key
// ("claude"), or { "key", "name", "run": [...], "icon"? } for your own command;
// "like": "claude" borrows a program's icon and name. Missing file: this list.
const DEFAULT_AGENTS = ["claude", "codex", "pi", "opencode"];
// Session readers' names to Herdr's program keys.
const PROGRAM = { claude: "claude", pi: "pi" };
const VARIANTS = { A: "Spotlight", B: "Columns", C: "Inbox" };

const tilde = (p) => (p === HOME ? "~" : p?.startsWith(HOME + "/") ? "~" + p.slice(HOME.length) : p);
const base = (p) => (p === HOME ? "~" : p.split("/").filter(Boolean).pop() ?? p);
const inside = (p, dir) => p === dir || p?.startsWith(dir + "/");
// Where a space is now: its first terminal's folder (space.folder is where it began).
function whereOf(s, all = panes()) {
  const tabs = new Set((s.tabs ?? []).map((c) => c.id));
  return all.find((p) => tabs.has(p.tab) && p.cwd)?.cwd || s.folder || null;
}
const openSpaces = () => { const all = panes(); return spaces().filter((s) => !s.machine).map((s) => ({ s, at: whereOf(s, all) })); };

function ago(sec) {
  const s = Date.now() / 1000 - sec;
  if (s < 3600) return `${Math.max(1, Math.round(s / 60))}m`;
  if (s < 86400) return `${Math.round(s / 3600)}h`;
  if (s < 86400 * 14) return `${Math.round(s / 86400)}d`;
  return `${Math.round(s / 86400 / 7)}w`;
}

function fuzzy(q, text) {
  const t = text.toLowerCase();
  let score = 0, at = 0, run = 0;
  const hits = [];
  for (const ch of q) {
    const i = t.indexOf(ch, at);
    if (i < 0) return null;
    const start = i === 0 || /[\s:.\-_/]/.test(t[i - 1]);
    run = i === at && hits.length ? run + 1 : 0;
    score += 1 + (start ? 6 : 0) + run * 3 - Math.min(i - at, 6) * 0.3;
    hits.push(i);
    at = i + 1;
  }
  return { score: score - text.length * 0.02, hits };
}

// Path match: the last folder name counts most (like fzf --scheme=path).
function pathScore(q, folder) {
  const name = fuzzy(q, base(folder));
  const full = fuzzy(q, tilde(folder));
  if (!name && !full) return null;
  return Math.max(name ? name.score + 8 : -99, full ? full.score : -99);
}

// One shell call for the side panel: branch, dirty count, worktrees, branches.
const GIT = `
cd "$1" 2>/dev/null || exit 1
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo NOGIT; exit 0; }
echo "TOP $(git rev-parse --show-toplevel)"
echo "COMMON $(cd "$(git rev-parse --git-common-dir)" && pwd)"
echo "BRANCH $(git branch --show-current)"
echo "DIRTY $(git status --porcelain 2>/dev/null | wc -l)"
git worktree list --porcelain | sed -n 's/^worktree /WT /p; s/^branch refs\\/heads\\//WB /p'
git for-each-ref --sort=-committerdate --count=40 --format='REF %(refname)\t%(committerdate:unix)' refs/heads refs/remotes/origin
`;

function parseGit(out) {
  if (out.startsWith("NOGIT")) return { git: false };
  const g = { git: true, worktrees: [], branches: [] };
  let wt = null;
  for (const line of out.split("\n")) {
    const [tag, ...rest] = line.split(" ");
    const v = rest.join(" ");
    if (tag === "TOP") g.top = v;
    else if (tag === "COMMON") g.common = v;
    else if (tag === "BRANCH") g.branch = v;
    else if (tag === "DIRTY") g.dirty = Number(v) || 0;
    else if (tag === "WT") { wt = { folder: v, branch: null }; g.worktrees.push(wt); }
    else if (tag === "WB" && wt) wt.branch = v;
    else if (tag === "REF") {
      const [ref, when] = v.split("\t");
      const remote = ref.startsWith("refs/remotes/");
      const name = ref.replace(/^refs\/(heads|remotes\/origin)\//, "");
      if (name === "HEAD" || name === "origin") continue;
      if (remote && g.branches.some((b) => b.name === name)) continue;
      g.branches.push({ name, when: Number(when), remote });
    }
  }
  // A branch checked out somewhere opens that checkout.
  for (const b of g.branches) b.worktree = g.worktrees.find((w) => w.branch === b.name)?.folder ?? null;
  return g;
}

export default class Launch extends View {
  init(_props, cx) {
    this.variant = localStorage.getItem("variant") ?? "A";
    this.query = "";
    this.input = InputState.new({ placeholder: "Search folders, sessions, agents…" });
    this.input.on("change", (_e, cx) => {
      this.query = this.input.value();
      if (this.silent) { this.silent = false; return cx.notify(); }
      this.at[this.variant === "B" ? this.col : 0] = 0;
      if (this.variant === "B" && this.col === 0) this.at = [0, 0, 0];
      if (this.variant !== "B") this.at[1] = 0;
      this.expanded = null;
      cx.notify();
    });
    this.input.focus();
    cx.timer.after(400, () => this.input.focus());
    this.handle = cx.focus_handle();
    // Tab would move the keyboard out of the launcher: claim it here.
    try {
      cx.bind_keys([
        { keystroke: "tab", action: "proto_launch_tab", context: "ProtoLaunch" },
        { keystroke: "shift-tab", action: "proto_launch_backtab", context: "ProtoLaunch" },
        // The search would take ←/→ for its cursor; the launcher uses them to move.
        { keystroke: "left", action: "proto_launch_left", context: "ProtoLaunch" },
        { keystroke: "right", action: "proto_launch_right", context: "ProtoLaunch" },
        { keystroke: "left", action: "proto_launch_left", context: "ProtoLaunch > Input" },
        { keystroke: "right", action: "proto_launch_right", context: "ProtoLaunch > Input" },
      ]);
    } catch (err) { this.bindError = String(err); }
    this.scrolls = [ScrollHandle.new(), ScrollHandle.new(), ScrollHandle.new()];
    this.at = [0, 0, 0];
    this.col = 0;
    this.expanded = null;
    this.live = false;
    this.last = null;
    this.zox = [];
    this.dirs = [];
    this.closed = [];
    this.sessions = [];
    this.known = [];
    this.programs = {};
    this.git = {};
    this.hist = JSON.parse(localStorage.getItem("hist") ?? "{}");
    this.agentFor = JSON.parse(localStorage.getItem("agentFor2") ?? "{}");
    this.loading = 4;
    const done = (cx) => { this.loading--; cx.notify(); };
    cx.spawn(async (cx) => {
      try {
        const r = await exec("zoxide", ["query", "-ls"]);
        this.zox = r.stdout.split("\n").map((l) => l.trim().match(/^([\d.]+)\s+(.+)$/)).filter(Boolean).map((m) => ({ folder: m[2], score: Number(m[1]) }));
      } catch {}
      try {
        const v = JSON.parse((await readTextFile(`${HOME}/.config/herdr-app/view.json`)) ?? "{}");
        this.closed = (v.recent ?? []).map((r) => r.folder).filter(Boolean);
      } catch {}
      done(cx);
    });
    cx.spawn(async (cx) => {
      try {
        const r = await exec("fd", ["-H", "-td", "-d3", "-E", ".git", "-E", "node_modules", "-E", ".cache", "-E", ".local", "-E", ".npm", "-E", ".cargo", "-E", ".rustup", "-E", ".claude/projects", "-E", ".pi/agent/sessions", "-E", "snapshots", "--absolute-path", ".", HOME]);
        this.dirs = r.stdout.split("\n").filter(Boolean).map((p) => p.replace(/\/$/, ""));
      } catch {}
      done(cx);
    });
    cx.spawn(async (cx) => {
      try {
        const r = await exec("python3", [`${MOD}/sessions.py`, "150"]);
        this.sessions = JSON.parse(r.stdout || "[]");
      } catch {}
      done(cx);
    });
    // TEST HOOK (agent screenshots): ~/.cache/proto-launch-test.json {variant, query, col, at}.
    cx.spawn(async (cx) => {
      try {
        const t = JSON.parse((await readTextFile(`${HOME}/.cache/proto-launch-test.json`)) ?? "null");
        if (t) {
          if (t.variant) this.variant = t.variant;
          if (t.query) { this.input.set_value(t.query); this.query = t.query; }
          this.pendingTest = t;
        }
      } catch {}
      cx.notify();
    });
    cx.spawn(async (cx) => {
      try {
        const all = await knownAgents();
        for (const a of all) this.programs[a.key] = a;
        let want = DEFAULT_AGENTS;
        try {
          const cfg = JSON.parse((await readTextFile(`${MOD}/agents.json`)) ?? "null");
          if (Array.isArray(cfg?.agents)) want = cfg.agents;
        } catch (err) { this.configError = `agents.json: ${err}`; }
        this.known = want.map((e) => {
          if (typeof e === "string") return this.programs[e]?.installed ? this.programs[e] : null;
          if (!e?.run?.length) return null;
          const like = this.programs[e.like] ?? {};
          return { ...like, key: e.key ?? e.name, name: e.name ?? like.name ?? e.run[0], run: e.run, icon: e.icon ?? like.icon ?? null, tint: e.icon ? Boolean(e.tint) : Boolean(like.tint) };
        }).filter(Boolean);
      } catch {}
      done(cx);
    });
  }

  close() { closeOverlay(props().overlay); }

  setVariant(v) {
    this.variant = v; this.col = 0; this.at = [0, 0, 0]; this.expanded = null;
    localStorage.setItem("variant", v);
    this.input.focus();
  }

  // ---- data -------------------------------------------------------------

  // Every place, deduplicated by folder, with what we know about it.
  places() {
    const map = new Map();
    const get = (folder) => {
      if (!folder) return null;
      if (!map.has(folder)) map.set(folder, { folder, z: 0, open: null, closed: false, sessions: [], scanned: false });
      return map.get(folder);
    };
    for (const { s, at } of openSpaces()) if (at) get(at).open = s;
    for (const f of this.closed) get(f).closed = true;
    for (const z of this.zox) get(z.folder).z = z.score;
    for (const s of this.sessions) get(s.folder).sessions.push(s);
    for (const d of this.dirs) { const p = map.get(d); if (p) p.scanned = true; else get(d).scanned = true; }
    return [...map.values()];
  }

  // Frecency without a query: open, then use (zoxide, sessions, our launches).
  weight(p) {
    const h = this.hist[p.folder];
    const newest = p.sessions[0]?.mtime ?? 0;
    const recency = newest ? Math.max(0, 14 - (Date.now() / 1000 - newest) / 86400) : 0;
    return (p.open ? 1000 : 0) + (p.open?.active ? 500 : 0) + Math.log2(1 + p.z) * 4 + recency + (h ? 6 + Math.log2(1 + h.n) * 3 : 0) + (p.closed ? 4 : 0);
  }

  rankPlaces() {
    const q = this.query.trim().toLowerCase().replace(/\s+/g, "");
    const all = this.places();
    if (!q) {
      return all.filter((p) => p.open || p.z || p.sessions.length || p.closed || this.hist[p.folder])
        .map((p) => ({ p, score: this.weight(p) })).sort((a, b) => b.score - a.score);
    }
    return all.map((p) => {
      const s = pathScore(q, p.folder);
      return s === null ? null : { p, score: s * 3 + Math.min(this.weight(p), 1500) / 60 };
    }).filter(Boolean).sort((a, b) => b.score - a.score).slice(0, 200);
  }

  gitOf(folder) {
    if (!folder) return null;
    if (!(folder in this.git)) {
      this.git[folder] = "loading";
      this.cx.spawn(async (cx) => {
        try {
          const r = await exec("sh", ["-c", GIT, "sh", folder], { timeout: 5000 });
          this.git[folder] = r.code === 0 ? parseGit(r.stdout) : { git: false };
        } catch { this.git[folder] = { git: false }; }
        cx.notify();
      });
    }
    return this.git[folder];
  }

  // Sessions that belong to a place: its folder and, for a repo, its worktrees.
  sessionsOf(folder) {
    const g = this.git[folder];
    const roots = g?.git ? [folder, ...g.worktrees.map((w) => w.folder)] : [folder];
    return this.sessions.filter((s) => roots.includes(s.folder));
  }

  agentsIn(folder) {
    const g = this.git[folder];
    const roots = g?.git ? [folder, ...g.worktrees.map((w) => w.folder)] : [folder];
    const ids = new Set(openSpaces().filter(({ at }) => roots.includes(at)).map(({ s }) => s.id));
    return agents().filter((a) => ids.has(a.space));
  }

  agentChoice(folder) {
    const want = this.agentFor[folder] ?? localStorage.getItem("lastAgent");
    return this.known.find((a) => a.key === want) ?? this.known[0] ?? null;
  }

  cycleAgent(folder) {
    if (!folder || !this.known.length) return;
    const cur = this.agentChoice(folder);
    const next = this.known[(this.known.indexOf(cur) + 1) % this.known.length];
    this.agentFor[folder] = next.key;
    localStorage.setItem("agentFor2", JSON.stringify(this.agentFor));
  }

  // ---- actions ----------------------------------------------------------

  // What = { folder, branch?, session?, agent? }, how = { shell, jump }.
  plan(what, how) {
    let folder = what.folder;
    if (what.branch) {
      if (!what.branch.worktree) return { title: `New worktree for ${what.branch.name}`, cmd: "(deferred: worktree create)", args: { branch: what.branch.name } };
      folder = what.branch.worktree;
    }
    if (what.session) folder = what.session.folder;
    const open = openSpaces().find(({ at }) => at === folder)?.s;
    if (how.jump && open) return { title: `Go to ${open.name}`, cmd: "space.select", args: { id: open.id } };
    if (what.focus) return { title: `Focus ${what.focus.title || what.focus.app}`, cmd: "agent.focus", args: { terminal: what.focus.address } };
    const agent = what.agent ?? this.agentChoice(folder);
    const argv = what.session ? what.session.argv : how.shell ? undefined : agent?.run;
    const label = what.session ? `Resume “${what.session.title}”` : how.shell ? "Shell" : agent?.name ?? "Shell";
    if (open) return { title: `${label} in ${open.name}`, cmd: "tab.new", args: { space: open.id, ...(argv ? { argv } : {}) }, folder, agent: !how.shell && !what.session ? agent : null };
    return { title: `${label} in ${tilde(folder)}`, cmd: "space.new", args: { folder, ...(argv ? { argv } : {}) }, folder, agent: !how.shell && !what.session ? agent : null };
  }

  go(what, how = {}) {
    if (!what) return;
    const p = this.plan(what, how);
    this.last = p;
    if (!this.live || p.cmd.startsWith("(")) return;
    if (p.folder) {
      const h = this.hist[p.folder] ?? { n: 0 };
      this.hist[p.folder] = { n: h.n + 1, at: Date.now() };
      localStorage.setItem("hist", JSON.stringify(this.hist));
    }
    if (p.agent) localStorage.setItem("lastAgent", p.agent.key);
    this.close();
    run(p.cmd, p.args);
  }

  // ---- shared pieces ------------------------------------------------------

  // A program's icon from Herdr's table: a one-color glyph or a picture.
  icon(p, size = 14, color) {
    if (!p?.icon) return div().size(size).flex_none();
    return p.tint ? svg(p.icon).size(size).flex_none().text_color(color) : image(p.icon).w(size).h(size).flex_none();
  }

  sessionIcon(t, s) { return this.icon(this.programs[PROGRAM[s.agent]], 14, t.muted); }

  // Agent status as the sidebar draws it: spinner, Needs you, dot (done), ring (idle).
  status(t, status) {
    if (status === "working") return svg("mods/workspace-chrome/spinner.svg").size(12).mx(1).flex_none().text_color(t.working).spin(900);
    if (status === "blocked") return div().size(14).flex_none().rounded(R).bg(t.blocked + "26").text_size(SMALL).font_bold().text_color(t.blocked).flex().items_center().justify_center().child("!");
    if (status === "done") return div().size(7).mx(3).flex_none().rounded_full().bg(t.done);
    return div().size(7).mx(3).flex_none().rounded_full().border(LINE).border_color(t.idle ?? t.dim);
  }

  dot(t, status, size = 7) {
    const c = { working: t.working, blocked: t.blocked, done: t.done, idle: t.idle }[status] ?? t.dim;
    return div().size(size).flex_none().rounded_full().bg(c);
  }

  tag(t, text, color) {
    return div().flex_none().text_size(SMALL).text_color(color ?? t.dim).child(text);
  }

  placeTags(t, p) {
    const tags = [];
    if (p.open) tags.push(this.tag(t, "open", t.accent));
    else if (p.closed) tags.push(this.tag(t, "closed"));
    if (inside(p.folder, `${HOME}/worktrees`)) tags.push(this.tag(t, "wt"));
    if (p.sessions.length) tags.push(this.tag(t, `${p.sessions.length} past`));
    if (p.open) tags.push(this.status(t, p.open.status));
    return tags;
  }

  row(t, id, on, children, click) {
    return h_flex().id(id).flex_none().h(30).px(S2).gap(S2).items_center().rounded(R).cursor_pointer()
      .text_size(TEXT).when(on, (el) => el.bg(t.selected)).hover((s) => s.bg(t.hover))
      .on_click(click).children(children);
  }

  search(t, folder) {
    const agent = folder ? this.agentChoice(folder) : null;
    return h_flex().h(36).flex_none().px(S2).gap(S2).items_center().rounded(R).border(LINE).border_color(t.accent).bg(t.background)
      .child(Input.new(this.input).flex_1().h_full().text_size(TEXT).text_color(t.foreground))
      .when(Boolean(this.loading), (el) => el.child(this.tag(t, "loading…")))
      .child(h_flex().flex_none().px(S1).gap(S1).items_center().border(LINE).border_color(t.border).rounded(R)
        .child(this.tag(t, "⇥", t.dim)).child(agent ? this.icon(agent, 16, t.foreground) : this.tag(t, "shell")).child(this.tag(t, agent?.name ?? "", t.muted)));
  }

  footer(t, hints) {
    const p = this.last;
    return v_flex().flex_none().gap(S1).pt(S2).border_t(LINE).border_color(t.border)
      .child(h_flex().gap(S3).text_size(SMALL).text_color(t.dim)
        .children(hints.map((h) => div().child(h)))
        .child(div().text_color(t.accent).child(`key: ${this.lastKey ?? "-"}${this.bindError ? ` bind error: ${this.bindError}` : ""}${this.configError ? ` ${this.configError}` : ""}`))
        .child(div().flex_1())
        .child(div().id("live").px(S1).rounded(R).border(LINE).border_color(this.live ? t.blocked : t.border)
          .text_color(this.live ? t.blocked : t.muted).cursor_pointer().hover((st) => st.bg(t.hover))
          .on_click((_e, cx) => { this.live = !this.live; this.input.focus(); cx.notify(); })
          .child(this.live ? "live: launches" : "dry run"))
        .children(Object.entries(VARIANTS).map(([k, v]) => div().id(`variant-${k}`).px(S1).rounded(R).border(LINE)
          .border_color(k === this.variant ? t.accent : t.border).text_color(k === this.variant ? t.accent : t.muted)
          .cursor_pointer().hover((st) => st.bg(t.hover))
          .on_click((_e, cx) => { this.setVariant(k); cx.notify(); })
          .child(v))))
      .when(Boolean(p), (el) => el.child(h_flex().gap(S2).text_size(SMALL)
        .child(div().text_color(t.foreground).child(p.title))
        .child(div().flex_1().min_w(0).truncate().text_color(t.muted).child(`${p.cmd} ${JSON.stringify(p.args)}`))));
  }

  frame(t, keys, children) {
    this.keysFn = keys;
    const send = (key, shift = false) => (_e, cx) => {
      this.lastKey = `${shift ? "shift-" : ""}${key} (action)`;
      this.keysFn({ key, keystroke: key, modifiers: { shift, control: false, alt: false, platform: false, function: false } });
      this.input.focus();
      cx.notify();
    };
    return v_flex().id("proto-launch").key_context("ProtoLaunch").track_focus(this.handle)
      .on_action("proto_launch_tab", send("tab")).on_action("proto_launch_backtab", send("tab", true))
      .on_action("proto_launch_left", send("left")).on_action("proto_launch_right", send("right")).w_full().h(HEIGHT).overflow_hidden().p(S3).gap(S2)
      .bg(t.popover).border(LINE).border_color(t.border).rounded(R)
      .on_key_down((e, cx) => {
        const k = e.key;
        this.lastKey = e.keystroke;
        if (k === "escape") {
          if (this.variant === "C" && this.expanded) { this.expanded = null; cx.stop_propagation(); cx.notify(); return; }
          if (this.col > 0) { this.col--; if (this.variant === "B") this.clearQuery(); cx.stop_propagation(); cx.notify(); return; }
          return this.close();
        }
        const f = { f1: "A", f2: "B", f3: "C" }[k];
        if (f) this.setVariant(f);
        else if (k === "f5") this.live = !this.live;
        else if (keys(e) === false) return;
        cx.stop_propagation();
        cx.notify();
      })
      .children(children);
  }

  // Scrolls a list so row i stays visible.
  list(id, n, i, rows) {
    this.scrolls[n].scroll_to_item(i);
    return div().flex_1().min_h(0).overflow_hidden().child(v_flex().id(id).size_full().overflow_y_scroll().track_scroll(this.scrolls[n]).children(rows));
  }

  move(n, len, k) {
    if (k === "down") this.at[n] = Math.min(this.at[n] + 1, len - 1);
    else if (k === "up") this.at[n] = Math.max(this.at[n] - 1, 0);
    else if (k === "pagedown") this.at[n] = Math.min(this.at[n] + 10, len - 1);
    else if (k === "pageup") this.at[n] = Math.max(this.at[n] - 10, 0);
    else return false;
    this.at[n] = Math.max(0, this.at[n]);
    return true;
  }

  how(e) { return { shell: e.modifiers.shift, jump: e.modifiers.control }; }

  render(cx) {
    this.cx = cx;
    if (this.pendingTest && !this.loading) {
      const t = this.pendingTest; this.pendingTest = null;
      if (t.col !== undefined) this.col = t.col;
      if (t.at) this.at = [...t.at];
      if (t.expand) this.expanded = t.expand;
      if (t.go) this.go({ folder: t.go });
    }
    const t = theme();
    if (this.variant === "B") return this.columns(t);
    if (this.variant === "C") return this.inbox(t);
    return this.spotlight(t);
  }

  // ---- A: Spotlight ---------------------------------------------------------
  // One ranked list; the side panel shows the selected place: branch, agents
  // running there, sessions to resume, branches and worktrees. → enters it.

  panelItems(folder) {
    const g = this.gitOf(folder);
    const items = [];
    for (const a of this.agentsIn(folder)) items.push({ kind: "agent", a, what: { folder, focus: a } });
    const live = new Set(this.agentsIn(folder).map((a) => (a.app === "claude-code" ? "claude" : a.app)));
    const hidden = new Set();
    const past = this.sessionsOf(folder).filter((s) => (live.has(s.agent) && !hidden.has(s.agent) ? (hidden.add(s.agent), false) : true));
    for (const s of past.slice(0, 5)) items.push({ kind: "session", s, what: { folder, session: s } });
    if (g?.git) for (const b of g.branches.filter((b) => b.name !== g.branch).slice(0, 40)) items.push({ kind: "branch", b, what: { folder, branch: b } });
    return items;
  }

  spotlight(t) {
    const ranked = this.rankPlaces();
    this.at[0] = Math.min(this.at[0], Math.max(0, ranked.length - 1));
    const sel = ranked[this.at[0]]?.p;
    const items = sel ? this.panelItems(sel.folder) : [];
    this.at[1] = Math.min(this.at[1], Math.max(0, items.length - 1));
    if (!items.length) this.col = 0;
    const keys = (e) => {
      const k = e.key;
      if (k === "tab") { this.cycleAgent(sel?.folder); return; }
      if (k === "right" && this.col === 0 && items.length) { this.col = 1; this.at[1] = 0; return; }
      if (k === "left" && this.col === 1) { this.col = 0; return; }
      if (k === "enter") {
        if (this.col === 1) this.go(items[this.at[1]]?.what, this.how(e));
        else if (sel) this.go({ folder: sel.folder }, this.how(e));
        return;
      }
      return this.move(this.col, this.col ? items.length : ranked.length, k);
    };
    const rows = ranked.map(({ p }, i) => this.row(t, `a-${i}`, i === this.at[0] && this.col === 0, [
      div().flex_none().w(150).truncate().text_color(t.foreground).child(base(p.folder)),
      div().flex_1().min_w(0).truncate().text_color(t.dim).text_size(SMALL).child(tilde(p.folder)),
      ...this.placeTags(t, p),
    ], () => { this.at[0] = i; this.col = 0; this.cx?.notify(); }).when(i === this.at[0] && this.col === 1, (el) => el.bg(t.hover)));
    return this.frame(t, keys, [
      this.search(t, sel?.folder),
      h_flex().flex_1().min_h(0).overflow_hidden().gap(S3)
        .child(v_flex().flex_1().h_full().min_w(0).min_h(0)
          .child(rows.length ? this.list("a-list", 0, this.at[0], rows) : div().p(S2).text_color(t.dim).text_size(TEXT).child(this.loading ? "Loading…" : "No matches")))
        .child(v_flex().w(330).h_full().flex_none().min_h(0).pl(S3).border_l(LINE).border_color(t.border).gap(S2)
          .child(sel ? this.panel(t, sel, items) : div())),
      this.footer(t, ["⏎ agent", "⇧⏎ shell", "^⏎ go to", "→ resume / branch", "⇥ agent"]),
    ]);
  }

  panel(t, p, items) {
    const g = this.git[p.folder];
    const head = v_flex().flex_none().gap(HAIR)
      .child(div().text_size(TEXT).font_semibold().text_color(t.foreground).truncate().child(tilde(p.folder)))
      .child(div().text_size(SMALL).text_color(t.muted).child(
        g === "loading" || !g ? "…" : g.git ? `${g.branch || "detached"} · ${g.dirty ? `${g.dirty} changed` : "clean"} · ${g.worktrees.length} checkout${g.worktrees.length === 1 ? "" : "s"}` : "not a git repo"));
    const sections = [];
    let last = null;
    let selIdx = 0;
    items.forEach((it, i) => {
      if (it.kind !== last) {
        sections.push(div().flex_none().pt(S1).text_size(SMALL).font_semibold().text_color(t.dim)
          .child({ agent: "Running here", session: "Resume", branch: "Branches" }[it.kind]));
        last = it.kind;
      }
      const on = this.col === 1 && i === this.at[1];
      if (on) selIdx = sections.length;
      const pick = () => { this.col = 1; this.at[1] = i; this.cx?.notify(); };
      if (it.kind === "agent") sections.push(this.row(t, `pa-${i}`, on, [this.icon(it.a.program, 14, t.muted), div().flex_1().min_w(0).truncate().child(it.a.title || it.a.app || "agent"), this.tag(t, it.a.tab_name), this.status(t, it.a.status)], pick));
      if (it.kind === "session") sections.push(this.row(t, `ps-${i}`, on, [this.sessionIcon(t, it.s), div().flex_1().min_w(0).truncate().text_color(it.s.titled ? t.foreground : t.muted).child(it.s.title), this.tag(t, ago(it.s.mtime))], pick));
      if (it.kind === "branch") sections.push(this.row(t, `pb-${i}`, on, [div().flex_1().min_w(0).truncate().child(it.b.name), this.tag(t, it.b.worktree ? "wt" : it.b.remote ? "origin" : ""), this.tag(t, ago(it.b.when))], pick));
    });
    return v_flex().flex_1().min_h(0).gap(S2)
      .child(head)
      .child(sections.length ? this.list("a-panel", 1, selIdx, sections)
        : div().text_size(SMALL).text_color(t.dim).child("Nothing to resume here yet."));
  }

  // ---- B: Columns -----------------------------------------------------------
  // Place → branch → how to start. ←/→ move between columns; typing filters
  // the column you're in; Enter launches what the three columns say.

  columns(t) {
    const q = this.query.trim().toLowerCase();
    const ranked = this.col === 0 ? this.rankPlaces() : (this.colPlaces ?? this.rankPlaces());
    if (this.col === 0) this.colPlaces = ranked;
    this.at[0] = Math.min(this.at[0], Math.max(0, ranked.length - 1));
    const sel = ranked[this.at[0]]?.p;
    const g = sel ? this.gitOf(sel.folder) : null;
    let branches = [{ name: g?.git ? `${g.branch || "detached"} (here)` : "(this folder)", here: true }];
    if (g?.git) branches.push(...g.branches.filter((b) => b.name !== g.branch));
    if (this.col === 1 && q) branches = branches.filter((b) => b.here || fuzzy(q, b.name));
    this.at[1] = Math.min(this.at[1], Math.max(0, branches.length - 1));
    const br = branches[this.at[1]];
    const folder = br && !br.here ? br.worktree : sel?.folder;
    let starts = [...this.known.map((a) => ({ label: a.name, agent: a })), { label: "Shell", shell: true }];
    if (folder) starts.push(...this.sessions.filter((s) => s.folder === folder).slice(0, 15).map((s) => ({ label: s.title, session: s })));
    if (this.col === 2 && q) starts = starts.filter((s) => fuzzy(q, s.label));
    if (this.col !== 2 && sel) {
      const want = this.agentChoice(folder ?? sel.folder);
      const i = starts.findIndex((s) => s.agent === want);
      if (this.at[2] === 0 && i > 0 && !this.touched2) this.at[2] = i;
    }
    this.at[2] = Math.min(this.at[2], Math.max(0, starts.length - 1));
    const st = starts[this.at[2]];
    const what = () => sel && ({ folder: sel.folder, branch: br && !br.here ? br : undefined, session: st?.session, agent: st?.agent });
    const keys = (e) => {
      const k = e.key;
      if (k === "right" || (k === "tab" && !e.modifiers.shift)) { if (this.col < 2) { this.col++; this.clearQuery(); } return; }
      if (k === "left" || (k === "tab" && e.modifiers.shift)) { if (this.col > 0) { this.col--; this.clearQuery(); } return; }
      if (k === "enter") return void this.go(what(), { shell: e.modifiers.shift || st?.shell, jump: e.modifiers.control });
      const moved = this.move(this.col, [ranked.length, branches.length, starts.length][this.col], k);
      if (moved && this.col === 0) { this.at[1] = 0; this.at[2] = 0; this.touched2 = false; }
      if (moved && this.col === 2) this.touched2 = true;
      return moved;
    };
    const column = (n, title, rows) => v_flex().flex_1().h_full().min_w(0).min_h(0).gap(S1)
      .when(n > 0, (el) => el.pl(S2).border_l(LINE).border_color(t.border))
      .child(div().flex_none().text_size(SMALL).font_semibold().text_color(this.col === n ? t.accent : t.dim).child(title))
      .child(this.list(`b-${n}`, n, this.at[n], rows));
    const mark = (n, i) => i === this.at[n];
    return this.frame(t, keys, [
      h_flex().gap(S2).items_center().child(div().flex_1().child(this.search(t, folder ?? sel?.folder)))
        .child(this.tag(t, `filtering: ${["places", "branches", "start"][this.col]}`)),
      h_flex().flex_1().min_h(0).overflow_hidden().gap(S2)
        .child(column(0, "PLACE", ranked.map(({ p }, i) => this.row(t, `b0-${i}`, mark(0, i), [
          div().flex_1().min_w(0).truncate().text_color(t.foreground).child(base(p.folder)), ...this.placeTags(t, p)],
          () => { this.col = 0; this.at[0] = i; this.cx?.notify(); }).when(this.col !== 0 && i === this.at[0], (el) => el.bg(t.hover)))))
        .child(column(1, "BRANCH", branches.map((b, i) => this.row(t, `b1-${i}`, mark(1, i) && this.col === 1, [
          div().flex_1().min_w(0).truncate().text_color(b.here ? t.foreground : t.muted).child(b.name),
          this.tag(t, b.here ? "" : b.worktree ? "wt" : b.remote ? "origin" : "new wt"), this.tag(t, b.when ? ago(b.when) : "")],
          () => { this.col = 1; this.at[1] = i; this.cx?.notify(); }).when(this.col !== 1 && i === this.at[1], (el) => el.bg(t.hover)))))
        .child(column(2, "START", starts.map((s, i) => this.row(t, `b2-${i}`, mark(2, i) && this.col === 2, [
          s.session ? this.sessionIcon(t, s.session) : s.agent ? this.icon(s.agent, 14, t.muted) : this.tag(t, "$"),
          div().flex_1().min_w(0).truncate().text_color(s.session && !s.session.titled ? t.muted : t.foreground).child(s.label),
          this.tag(t, s.session ? ago(s.session.mtime) : "")],
          () => { this.col = 2; this.at[2] = i; this.touched2 = true; this.cx?.notify(); }).when(this.col !== 2 && i === this.at[2], (el) => el.bg(t.hover))))),
      this.footer(t, ["←/→ column", "⏎ launch", "⇧⏎ shell", "^⏎ go to"]),
    ]);
  }

  clearQuery() {
    if (!this.query) return;
    this.query = "";
    this.silent = true;
    this.input.set_value("");
  }

  // ---- C: Inbox ---------------------------------------------------------------
  // Work first, folders second: agents running now, sessions to pick up, then
  // places. Typing searches all three (session titles too). → on a place opens
  // its branches inline.

  inbox(t) {
    const q = this.query.trim().toLowerCase();
    const qq = q.replace(/\s+/g, "");
    const names = new Map(spaces().map((s) => [s.id, s]));
    const where = new Map(openSpaces().map(({ s, at }) => [s.id, at]));
    let running = agents().map((a) => ({ a, s: names.get(a.space) })).filter((x) => x.s && !x.s.machine);
    // A running agent's own session isn't something to pick up: hide the newest
    // session per folder and agent that has one running there.
    const live = new Set(running.map(({ a, s }) => `${where.get(s.id)}|${a.app === "claude-code" ? "claude" : a.app}`));
    const seen = new Set();
    const resumable = this.sessions.filter((x) => {
      const k = `${x.folder}|${x.agent}`;
      if (!live.has(k) || seen.has(k)) return true;
      seen.add(k);
      return false;
    });
    let pickup = resumable.slice(0, 40);
    let places = this.rankPlaces();
    if (q) {
      running = running.map((x) => ({ x, sc: fuzzy(qq, `${x.a.title} ${x.s.name}`) })).filter((y) => y.sc).sort((a, b) => b.sc.score - a.sc.score).map((y) => y.x);
      pickup = resumable.map((s) => ({ s, sc: Math.max(fuzzy(qq, s.title)?.score ?? -99, (pathScore(qq, s.folder) ?? -99) - 2) })).filter((y) => y.sc > -99).sort((a, b) => b.sc - a.sc).map((y) => y.s).slice(0, 25);
    } else {
      places = places.filter(({ p }) => !p.open);
    }
    places = places.slice(0, 60);
    const rows = [];
    const add = (head, items) => { if (items.length) rows.push({ head }, ...items); };
    add("RUNNING", running.map(({ a, s }) => ({ kind: "agent", a, s, what: { folder: where.get(s.id), focus: a } })));
    add("PICK UP", pickup.map((s) => ({ kind: "session", s, what: { folder: s.folder, session: s } })));
    const pl = [];
    for (const { p } of places) {
      pl.push({ kind: "place", p, what: { folder: p.folder } });
      if (this.expanded === p.folder) {
        const g = this.gitOf(p.folder);
        if (g === "loading") pl.push({ kind: "note", text: "loading branches…" });
        else if (!g?.git) pl.push({ kind: "note", text: "not a git repo" });
        else for (const b of g.branches.filter((b) => b.name !== g.branch).slice(0, 15)) pl.push({ kind: "branch", b, what: { folder: p.folder, branch: b } });
      }
    }
    add("PLACES", pl);
    const pickable = rows.map((r, i) => (r.what ? i : -1)).filter((i) => i >= 0);
    this.at[0] = Math.min(this.at[0], Math.max(0, pickable.length - 1));
    const cur = rows[pickable[this.at[0]]];
    const keys = (e) => {
      const k = e.key;
      if (k === "tab") { this.cycleAgent(cur?.what?.folder); return; }
      if (k === "right" && cur?.kind === "place") { this.expanded = cur.p.folder; return; }
      if (k === "left" && this.expanded) {
        const back = pickable.findIndex((i) => rows[i].kind === "place" && rows[i].p.folder === this.expanded);
        this.expanded = null; if (back >= 0) this.at[0] = back; return;
      }
      if (k === "enter") return void this.go(cur?.what, this.how(e));
      return this.move(0, pickable.length, k);
    };
    const els = rows.map((r, i) => {
      const n = pickable.indexOf(i);
      const on = n === this.at[0];
      const pick = () => { this.at[0] = n; this.cx?.notify(); };
      if (r.head) return div().flex_none().pt(S2).pb(S1).px(S2).text_size(SMALL).font_semibold().text_color(t.dim).child(r.head);
      if (r.kind === "note") return div().flex_none().pl(40).h(24).text_size(SMALL).text_color(t.dim).child(r.text);
      if (r.kind === "agent") return this.row(t, `c-${i}`, on, [this.icon(r.a.program, 14, t.muted),
        div().flex_1().min_w(0).truncate().text_color(t.foreground).child(r.a.title || r.a.app || "agent"),
        this.tag(t, `${r.s.name} · ${r.a.tab_name}`), this.status(t, r.a.status)], pick);
      if (r.kind === "session") return this.row(t, `c-${i}`, on, [this.sessionIcon(t, r.s),
        div().flex_1().min_w(0).truncate().text_color(r.s.titled ? t.foreground : t.muted).child(r.s.title),
        this.tag(t, base(r.s.folder)), this.tag(t, ago(r.s.mtime))], pick);
      if (r.kind === "branch") return this.row(t, `c-${i}`, on, [div().w(20).flex_none(), this.tag(t, "⎇"),
        div().flex_1().min_w(0).truncate().child(r.b.name), this.tag(t, r.b.worktree ? "wt" : r.b.remote ? "origin" : "new wt"), this.tag(t, ago(r.b.when))], pick);
      return this.row(t, `c-${i}`, on, [this.tag(t, this.expanded === r.p.folder ? "▾" : "▸"),
        div().flex_none().w(170).truncate().text_color(t.foreground).child(base(r.p.folder)),
        div().flex_1().min_w(0).truncate().text_size(SMALL).text_color(t.dim).child(tilde(r.p.folder)), ...this.placeTags(t, r.p)], pick);
    });
    const folder = cur?.what?.session?.folder ?? cur?.what?.folder;
    return this.frame(t, keys, [
      this.search(t, folder),
      els.length ? this.list("c-list", 0, pickable[this.at[0]] ?? 0, els) : div().flex_1().p(S2).text_color(t.dim).child(this.loading ? "Loading…" : "No matches"),
      this.footer(t, ["⏎ open / resume / focus", "⇧⏎ shell", "^⏎ go to", "→ branches", "⇥ agent"]),
    ]);
  }
}

