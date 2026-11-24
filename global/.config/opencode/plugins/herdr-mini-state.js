// Complement to herdr-agent-state.js for `opencode mini --standalone` in OpenCode v2.
//
// `herdr-core` tracks live agent status via OSC 7501 sequences on the pane's PTY.
// Full `opencode` emits those from its TUI; `opencode mini --standalone` runs
// `opencode serve --stdio --port 0` in a child process and doesn't emit OSC 7501
// or run TUI plugins. Writing OSC 7501 to the parent PTY from OpenCode v2's
// `setup(ctx)` event stream bridges its lifecycle into `herdr-core` and Herdr's
// Agents tab.
import fs from "node:fs";
import { execFileSync } from "node:child_process";

const CHILD_EVENT_STATES = new Map([
  ["permission.asked", "blocked"],
  ["question.asked", "blocked"],
  ["session.permission.asked", "blocked"],
  ["session.question.asked", "blocked"],
  ["permission.replied", "working"],
  ["question.replied", "working"],
  ["question.rejected", "working"],
]);

const childSessions = new Map();
let rootSessionID = null;
let lastState = null;
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

    const stream = ctx?.event?.subscribe?.({});
    if (!stream || typeof stream[Symbol.asyncIterator] !== "function") {
      return;
    }

    void (async () => {
      try {
        for await (const event of stream) {
          const type = event?.type;
          const data = event?.data ?? event?.properties ?? {};
          const sessionID =
            typeof data?.sessionID === "string" && data.sessionID
              ? data.sessionID
              : undefined;

          const info = data.info;
          const parentID = info?.parentID ?? data.parentID;
          const infoID = info?.id ?? sessionID;
          if (infoID && parentID) {
            childSessions.set(infoID, parentID);
          }

          if (sessionID && childSessions.has(sessionID)) {
            const state = CHILD_EVENT_STATES.get(type);
            if (state) emitOsc7501(state);
            continue;
          }

          if (sessionID && !rootSessionID && !childSessions.has(sessionID)) {
            rootSessionID = sessionID;
          }

          switch (type) {
            case "session.execution.started":
            case "session.step.started":
            case "session.inbox.delivered":
            case "permission.replied":
            case "question.replied":
            case "question.rejected":
            case "session.compacted":
              emitOsc7501("working");
              break;
            case "permission.asked":
            case "question.asked":
            case "session.permission.asked":
            case "session.question.asked":
            case "session.execution.failed":
            case "session.error":
              emitOsc7501("blocked");
              break;
            case "session.execution.succeeded":
            case "session.execution.cancelled":
            case "session.execution.aborted":
            case "session.idle":
              if (!sessionID || !rootSessionID || sessionID === rootSessionID) {
                emitOsc7501("idle");
              }
              break;
            default:
              break;
          }
        }
      } catch {
        // Stream closed on shutdown.
      }
    })();
  },
};
