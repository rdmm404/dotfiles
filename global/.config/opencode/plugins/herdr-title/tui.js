import { reportTitle } from "../../../herdr/title-report.mjs"

export default {
  id: "herdr-title.tui",
  setup(ctx) {
    if (process.env.HERDR_ENV !== "1") return
    let disposed = false
    let lastKey
    let sentAt = 0
    let pending = false
    function selected() {
      const route = ctx.ui.router.current()
      if (route.type !== "session") return
      return ctx.data.session.get(ctx.data.session.root(route.sessionID) ?? route.sessionID)
    }
    async function publish() {
      if (disposed || pending) return
      const session = selected()
      if (!session) return
      const key = JSON.stringify([session.id, session.title])
      if (key === lastKey && Date.now() - sentAt < 15000) return
      pending = true
      try {
        const ok = await reportTitle("opencode", session.title,
          () => !disposed && selected()?.id === session.id && selected()?.title === session.title)
        if (ok) { lastKey = key; sentAt = Date.now() }
      } finally { pending = false }
    }
    // Polling also catches route changes, which aren't server events.
    const timer = setInterval(() => void publish(), 500)
    void publish()
    return () => { disposed = true; clearInterval(timer) }
  },
}
