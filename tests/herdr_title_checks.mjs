import assert from "node:assert/strict"
import { test } from "node:test"
import net from "node:net"
import { mkdtemp, rm } from "node:fs/promises"
import { reportTitle } from "../global/.config/herdr/title-report.mjs"
import opencodePlugin from "../global/.config/opencode/plugins/herdr-title/tui.js"

test("metadata reports presentation without overwriting lifecycle", async () => {
  const dir = await mkdtemp("/tmp/opencode/herdr-title-test-")
  const socket = `${dir}/test.sock`
  let request
  const server = net.createServer((client) => client.once("data", (data) => {
    request = JSON.parse(String(data))
    client.end('{"result":{}}\n')
  }))
  await new Promise((resolve) => server.listen(socket, resolve))
  const saved = { ...process.env }
  Object.assign(process.env, { HERDR_ENV: "1", HERDR_SOCKET_PATH: socket, HERDR_PANE_ID: "w1:p2" })
  try {
    assert.equal(await reportTitle("pi", "Fix\nparser"), true)
    assert.equal(request.method, "pane.report_metadata")
    assert.deepEqual(request.params.tokens, { title: "Fix parser", kind: "π" })
    assert.equal(request.params.title, "Fix parser")
    assert.equal(request.params.applies_to_source, "herdr:pi")
    assert.equal(request.params.state, undefined)
    assert.equal(await reportTitle("pi", ""), true)
    assert.equal(request.params.clear_title, true)
    assert.equal(request.params.tokens.title, "Pi")
    assert.equal(await reportTitle("pi", "stale", () => false), false)
    assert.equal(await reportTitle("opencode", "OpenCode session"), true)
    assert.equal(request.params.tokens.kind, "oc")
  } finally {
    process.env = saved
    await new Promise((resolve) => server.close(resolve))
    await rm(dir, { recursive: true })
  }
})

const settle = () => new Promise((resolve) => setTimeout(resolve, 50))

test("OpenCode reports only the TUI's selected root session and follows renames", async () => {
  const dir = await mkdtemp("/tmp/opencode/herdr-title-test-")
  const socket = `${dir}/test.sock`
  const requests = []
  const server = net.createServer((client) => client.once("data", (data) => {
    requests.push(JSON.parse(String(data)))
    client.end('{"result":{}}\n')
  }))
  await new Promise((resolve) => server.listen(socket, resolve))
  const saved = { ...process.env }
  Object.assign(process.env, { HERDR_ENV: "1", HERDR_SOCKET_PATH: socket, HERDR_PANE_ID: "w1:p2" })
  let route = { type: "session", sessionID: "child" }
  const sessions = {
    root: { id: "root", title: "Root title" },
    child: { id: "child", title: "Subagent title" },
    other: { id: "other", title: "Other client's title" },
  }
  const cleanup = opencodePlugin.setup({
    ui: { router: { current: () => route } },
    data: { session: { root: (id) => id === "child" ? "root" : id, get: (id) => sessions[id] } },
  })
  try {
    await settle()
    assert.equal(requests[0].params.title, "Root title")
    sessions.root = { id: "root", title: "Renamed root" }
    await new Promise((resolve) => setTimeout(resolve, 550))
    assert.equal(requests.at(-1).params.title, "Renamed root")
    route = { type: "session", sessionID: "other" }
    await new Promise((resolve) => setTimeout(resolve, 550))
    assert.equal(requests.at(-1).params.title, "Other client's title")
    assert.equal(requests.some((request) => request.params.title === "Subagent title"), false)
  } finally {
    cleanup()
    process.env = saved
    await new Promise((resolve) => server.close(resolve))
    await rm(dir, { recursive: true })
  }
})
