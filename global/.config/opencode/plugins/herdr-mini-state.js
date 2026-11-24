// Complement to herdr-agent-state.js for `opencode mini --standalone` in OpenCode v2.
//
// `herdr-core` tracks live agent status via OSC 7501 sequences on the pane's PTY.
// Full `opencode` emits those from its TUI; `opencode mini --standalone` runs
// `opencode serve --stdio --port 0` in a child process and doesn't emit OSC 7501
// or run TUI plugins. Writing OSC 7501 to `/dev/tty` from the server `setup(ctx)`
// hook bridges its lifecycle into `herdr-core` and Herdr's Agents tab.
import fs from "node:fs";
import { execFileSync } from "node:child_process";

const SESSION_STATE_BY_STATUS = new Map([
  ["idle", "idle"],
  ["active", "working"],
  ["busy", "working"],
  ["pending", "working"],
  ["retry", "working"],
  ["running", "working"],
  ["streaming", "working"],
  ["working", "working"],
]);

const CHILD_EVENT_STATES = new Map([
  ["permission.asked", "blocked"],
  ["question.asked", "blocked"],
  ["permission.replied", "working"],
  ["question.replied", "working"],
  ["question.rejected", "working"],
]);

const childSessions = new Map();
let lastState = null;

function sessionIDFromProperties(properties) {
  return typeof properties?.sessionID === "string" && properties.sessionID
    ? properties.sessionID
    : undefined;
}

function stateFromSessionStatus(status) {
  const kind = typeof status === "string" ? status : status?.type;
  return typeof kind === "string"
    ? SESSION_STATE_BY_STATUS.get(kind.toLowerCase())
    : undefined;
}

let ttyPath = null;

function resolveTtyPath() {
  if (ttyPath) return ttyPath;
  try {
    const fd = fs.openSync("/dev/tty", "w");
    fs.closeSync(fd);
    ttyPath = "/dev/tty";
    return ttyPath;
  } catch {}
  try {
    const out = execFileSync("ps", ["-o", "tty=", "-p", String(process.ppid)], {
      encoding: "utf8",
      timeout: 500,
    }).trim();
    if (out && out !== "??" && out !== "?") {
      const dev = out.startsWith("/dev/") ? out : `/dev/${out}`;
      const fd = fs.openSync(dev, "w");
      fs.closeSync(fd);
      ttyPath = dev;
      return ttyPath;
    }
  } catch {}
  return null;
}

function emitOsc7501(state) {
  if (!state || state === lastState) return;
  const dev = resolveTtyPath();
  if (!dev) return;
  try {
    const fd = fs.openSync(dev, "w");
    try {
      fs.writeSync(fd, `\x1b]7501;state=${state}\x07`);
      lastState = state;
    } finally {
      fs.closeSync(fd);
    }
  } catch {
    // Ignore write errors if tty is gone.
  }
}

function isMiniStandalone() {
  const args = process.argv.slice(2);
  const separator = args.indexOf("--");
  if (separator !== -1) args.splice(separator);
  while (
    args[0] === "--print-logs" ||
    args[0] === "--log-level" ||
    args[0]?.startsWith("--log-level=")
  ) {
    args.splice(0, args[0] === "--log-level" ? 2 : 1);
  }
  return (
    args[0] === "mini" ||
    (args[0] === "serve" && args.includes("--stdio"))
  );
}

export default {
  id: "herdr.opencode.mini",
  async setup(ctx) {
    if (!isMiniStandalone() || !process.env.HC_TERMINAL_ID) {
      return;
    }

    // Register immediately so the pane appears in Agents even before the first prompt.
    emitOsc7501("idle");

    ctx?.event?.subscribe?.((event) => {
      const type = event?.type;
      const properties = event?.properties ?? {};
      const sessionID = sessionIDFromProperties(properties);

      const info = properties.info;
      if (info?.id && info.parentID) {
        childSessions.set(info.id, info.parentID);
      }
      if (sessionID && childSessions.has(sessionID)) {
        const state = CHILD_EVENT_STATES.get(type);
        if (state) emitOsc7501(state);
        return;
      }

      switch (type) {
        case "session.status": {
          const state = stateFromSessionStatus(properties.status);
          if (state) emitOsc7501(state);
          break;
        }
        case "permission.replied":
        case "question.replied":
        case "question.rejected":
        case "session.compacted":
          emitOsc7501("working");
          break;
        case "permission.asked":
        case "question.asked":
        case "session.error":
          emitOsc7501("blocked");
          break;
        case "session.idle":
          emitOsc7501("idle");
          break;
        default:
          break;
      }
    });
  },
};
