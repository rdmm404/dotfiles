// Prefix bar: after the prefix key (keys.json: "ctrl-space": "mod.open:prefix")
// this bar lists the keys in BINDINGS below and runs the one pressed.
// Any other key, or Esc, closes it. Saving this file updates the bar at once.

import { View, div } from "gpui-kit";
import { h_flex } from "gpui-base";
import { commands, props, run, closeOverlay, theme, settings, shared } from "herdr";

const PREFIX = "ctrl-space";

// Keys available after the prefix: key -> app command, spelled as in
// keys.json ("name" or "name:value"). Kept here rather than in a separate
// module: the app refuses to import a symlinked file, and this one is
// symlinked from the dotfiles repo.
const BINDINGS = {
  "c": "tab.new",
  "r": "tab.rename",
  "k": "tab.close",
  "n": "tab.next",
  "p": "tab.prev",
  "1": "tab.select:1",
  "2": "tab.select:2",
  "3": "tab.select:3",
  "4": "tab.select:4",
  "5": "tab.select:5",
  "6": "tab.select:6",
  "7": "tab.select:7",
  "8": "tab.select:8",
  "9": "tab.select:9",
  "h": "pane.split:down",
  "v": "pane.split:right",
  "x": "pane.close",
  "z": "pane.zoom",
  "shift-c": "space.new",
  "shift-r": "space.rename",
  "shift-k": "space.close",
  "shift-n": "space.next",
  "shift-p": "space.prev",
  "shift-s": "app.settings",
  "?": "app.help",
  "d": "window.close",
};
const MODIFIER_KEYS = new Set(["shift", "control", "ctrl", "alt", "super", "cmd", "meta", "fn", "win", "platform", "function"]);

// Rows to show: runs of digit keys with the same command fold into one ("1-9").
function rows() {
  const out = [];
  for (const [key, action] of Object.entries(BINDINGS)) {
    const [name, arg] = action.split(":");
    const text = name.replace(/[._]/g, " ");
    const last = out[out.length - 1];
    const digit = /^\d$/.test(key) && arg === key;
    if (digit && last && last.digits && last.name === name) last.key = `${last.first}-${key}`;
    else if (digit) out.push({ key, first: key, digits: true, name, text });
    else out.push({ key, text: arg ? `${text} ${arg}` : text });
  }
  return out;
}

// The flat layout has its own copies of Herdr's screens and dialogs
// (mods/flat-*); there these bindings open those instead.
const FLAT = {
  "app.settings": ["mod.open", { name: "flat-settings" }],
  "app.help": ["mod.open", { name: "flat-help" }],
  "tab.rename": ["flat-tabs.rename-tab"],
  "tab.close": ["flat-tabs.close-tab"],
  "space.rename": ["flat-tabs.rename-space"],
  "space.close": ["flat-tabs.close-space"],
};

function invoke(action) {
  if (shared("layout") === "flat" && FLAT[action]) return run(...FLAT[action]);
  const at = action.indexOf(":");
  if (at < 0) return run(action, {});
  const name = action.slice(0, at);
  const value = action.slice(at + 1);
  const first = commands().find((c) => c.name === name)?.args[0]?.name;
  if (!first) return run(name, {});
  return run(name, { [first]: first === "index" ? Number(value) : value });
}

export default class Prefix extends View {
  init(_props, cx) {
    this.handle = cx.focus_handle();
    this.handle.focus();
    cx.timer.after(40, () => this.handle.focus());
    cx.timer.after(200, () => this.handle.focus());
  }

  press(e) {
    if (MODIFIER_KEYS.has(e.key)) return;
    const tried = [e.keystroke, e.key_char, e.key, e.modifiers?.shift ? `shift-${e.key}` : null];
    const key = tried.find((k) => k && Object.hasOwn(BINDINGS, k));
    closeOverlay(props().overlay);
    if (key) invoke(BINDINGS[key]);
  }

  render(cx) {
    const t = theme();
    // mod.json opens this as a full-width popup at a y far past the window:
    // the app clamps it to the bottom edge, over the status bar. Its height
    // follows the wrapped rows, so it fits any window width.
    return h_flex()
      .id("prefix")
      .track_focus(this.handle)
      .on_key_down((e, cx) => this.press(e))
      .w_full()
      .items_start()
      .gap(15)
      .px(15)
      .py(8)
      .bg(t.chrome)
      .border_t(1)
      .border_color(t.accent)
      .font_family(settings().font_family ?? "JetBrains Mono")
      .text_size(13)
      .child(div().flex_none().px(5).rounded(2).bg(t.accent).text_color(t.accent_foreground).font_semibold().child(PREFIX))
      .child(
        h_flex()
          .flex_1()
          .min_w(0)
          .flex_wrap()
          .gap_x(20)
          .gap_y(4)
          .children(
            rows().map((r) =>
              h_flex()
                .flex_none()
                .gap(8)
                .child(div().text_color(t.accent).child(r.key))
                .child(div().text_color(t.foreground).child(r.text)),
            ),
          ),
      );
  }
}
