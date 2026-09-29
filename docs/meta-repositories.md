# Meta repositories

A meta repository holds no service code of its own. It has a manifest and a sync script that clone each service into a gitignored directory such as `source/`. Ralph works in one of these just as it does in an ordinary repository.

## What changes

- **Commits anywhere count as progress.** Ralph watches every git repository beneath the workspace, not just the workspace's own. A pass that only commits inside `source/svc` is progress, not a no-op. The scan follows symlinks and goes 6 levels deep.
- **Ralph pushes the workspace only.** If the workspace has no `origin`, or no commits yet, ralph skips the push and carries on. A push that git rejects is still a failure.
- **The agent commits where each file lives.** The build prompt finds the repository that owns each changed file and runs its git commands, push included, there.
- **The plan and progress log stay at the root.** `IMPLEMENTATION_PLAN.md` and `PROGRESS.md` always live where you ran ralph, whatever the goal points at. The goal can name a spec anywhere below the root: inside a service's clone for a single-service feature, or in the workspace's own `specs/` for a feature that spans services.

## Set up your guardrails

In the workspace's `CLAUDE.md` or `AGENTS.md`:

- Name each service's own conventions file, so the agent reads it before committing there.
- If the sync script leaves clones on a detached `HEAD`, name the branch the agent should commit on.

Metrics count git activity in the workspace only. A pass that commits only in a nested repository records 0 commits, but is not marked as a no-op.

## Troubleshooting

**`build` stops after two passes while the agent is committing.** Check that no clone sits more than 6 levels below the workspace, since the scan can't see it. And don't pass `--skip-push` out of habit: ralph already skips the push when there is no `origin`, and the flag would leave real workspace commits unpushed.

**`plan` converged after one pass, but the plan is empty.** The agent wrote the plan somewhere else, usually because a stale project-local `PROMPT_plan.md` doesn't pin the plan to the workspace root. Re-run `install.sh`, then delete or refresh any `PROMPT_*.md` in the project.
