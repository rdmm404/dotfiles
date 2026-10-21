// Blocks plain git worktree creation and points the agent at the using-worktrees skill.
const MSG =
  "Blocked: don't create git worktrees directly. Load the `using-worktrees` skill " +
  "(skill tool, id `using-worktrees`) and follow it instead."

const GIT_WT_ADD = /\bgit\b(?:\s+(?:-[Cc]\s+\S+|--?\S+))*\s+worktree\s+add\b/

export default {
  id: "block-worktrees",
  async setup(ctx) {
    await ctx.tool.hook("execute.before", (event) => {
      if (event.tool === "opencode_worktree_create") throw new Error(MSG)
      if (event.tool === "shell" && GIT_WT_ADD.test(String(event.input?.command ?? ""))) {
        throw new Error(MSG)
      }
    })
  },
}
