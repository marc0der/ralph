---
id: "024"
created: 2026-11-23
area: [build, git, config]
amends: ["011", "013"]
related: ["017", "019"]
---

# Nested Push

Ralph pushes the workspace after each build or fix iteration, and `skip_push` gates that push.
The agent pushes every nested repository it commits in, because `prompts/build.md` tells it to,
and nothing tells the agent about `skip_push`. This spec moves every push to Ralph, so one
setting governs all of them.

This spec replaces the sentence "Ralph pushes nothing nested" in `011-nested-git-repos.md` §7,
and the matching items in its §9. It amends `013-meta-repo-hardening.md` §1 rule 3, where
pushing a nested repository is the agent's step, and §5 where the prompt states that step. §3 of
013 stands and now applies to each repository.

## 1. Problem

A run with `skip_push: true` built 9 items in `sdkman-broker-2`, a nested repository of a meta
workspace. The workspace push was skipped. The agent followed `prompts/build.md`:

> Push every repository you committed in, from inside it: `git -C <toplevel> push` …

It pushed `feature/cli-version-by-tag` to `origin` after each item. The operator had asked for no
pushes. The branch was a feature branch, so nothing was deployed. On a branch that deploys on push,
the same run would have deployed unreviewed work.

## 2. Rule

- **Ralph pushes, the agent never does.** `prompts/build.md` carries no push step.
- **The push set.** After each build or fix iteration, Ralph pushes:
  - every nested repository whose `HEAD` differs from its line in `.ralph/cycle-base`, or that
    the base does not list, and
  - the workspace, as today, whether or not it moved.
- **One gate.** `skip_push`, `--skip-push`, `--push` and `--dry-run` govern every push in the
  set, exactly as they govern the workspace push today.
- **Deepest first.** Ralph pushes nested repositories in order of path depth, deepest first, and
  the workspace last. A submodule gitlink then never reaches a remote before the commit it points
  at.

## 3. Behaviour

### The push block

The build-mode push block in `cmd_loop` calls `push_cycle_repos` before the existing workspace
push:

1. Take `repo_state` after the pass. Keep each line whose repository is not `.`, whose SHA is
   not `-`, and whose SHA differs from the repository's line in `.ralph/cycle-base` or has no line
   there.
2. Sort the kept repositories by the number of `/` in the path, most first, then by path.
3. For each repository:

   | Condition | Result |
   |-----------|--------|
   | `git -C <repo> remote get-url origin` fails | `No 'origin' remote in <repo> — skipping push.` |
   | `git -C <repo> symbolic-ref -q --short HEAD` fails | `Detached HEAD in <repo> — skipping push.` |
   | the branch has no upstream (`git -C <repo> rev-parse --abbrev-ref @{u}` fails) | `git -C <repo> push -u origin <branch>` |
   | otherwise | `git -C <repo> push origin <branch>` |

4. A push that git rejects prints `Push failed in <repo>:` with git's output and exits 1. Ralph
   pushes no further repository and not the workspace. `auto` records the failure in
   `.ralph/auto-state` as it does for a rejected workspace push.
5. Output follows the workspace push: git's output on stderr unless `--quiet`.

The workspace push that follows is unchanged (`013-meta-repo-hardening.md` §3).

With `--dry-run`, the block prints one `[dry-run] Would run: git -C <repo> push origin <branch>`
line per repository in the set, then the workspace line it prints today. A dry run runs none of
the checks in step 3, as the workspace dry run runs none, and prints `HEAD` as the branch of a
repository on a detached `HEAD`. A dry run writes no base, so the missing-base rule below decides
its set. With `skip_push`, it pushes nothing and prints nothing new.

### Why the cycle base

The base marks where the cycle began. A nested repository that moved since then carries this
cycle's commits, including those an earlier `skip_push` iteration or a failed push left local. A
sibling repository that holds the operator's own unpushed work did not move, so Ralph leaves it
alone.

A build writes the base before its first iteration (`write_cycle_base`), and a fix runs after
that build, so the base exists whenever the block runs. If it is missing anyway, every nested
repository whose SHA is not `-` counts as moved.

### `prompts/build.md`

- **Where to commit** loses the bullet "Push every repository you committed in …". It gains:
  "Never run `git push`. Ralph pushes every repository the cycle moved after this iteration."
- Phase 4 loses step 4, "Push as **Where to commit** states.", and its step 5 becomes step 4.
- The detached-`HEAD` rule still makes the agent check out a branch before it commits, so a
  repository the cycle moved is normally on a branch Ralph can push.

### Help and README

`--skip-push` and `--push` say "every repository the cycle moved, and the workspace" in place of
the workspace alone.

## 4. Documentation

- `docs/meta-repositories.md`: "Ralph pushes the workspace only" becomes "Ralph pushes the
  workspace and every nested repository the cycle moved". The paragraph on spec commits says a
  nested spec commit is pushed with the first build commit in that repository.
- `README.md`: the `--skip-push` and `--push` rows, the `skip_push` key row, and the paragraph on
  rejected pushes. The key table has no description column, so one sentence below it says that
  `skip_push` governs every repository the cycle moved, and the workspace. The paragraph on
  rejected pushes says Ralph names the repository whose push git rejected.
- `CLAUDE.md`: core loop step 7 says Ralph pushes every repository the cycle moved, deepest
  first, then the workspace.

## 5. Testing

`test/pipeline.bats` unless stated otherwise.

- A mock backend that commits in a nested repository with an `origin` causes one push of that
  repository's branch. The bare remote holds the commit afterwards.
- The same run with `--skip-push` leaves the bare remote unchanged.
- `--dry-run` prints the nested `[dry-run]` line before the workspace line.
- A nested repository the cycle did not move is not pushed, even when it has unpushed commits.
- A repository absent from the base is pushed.
- A nested repository with no `origin` and one on a detached `HEAD` each print their skip line,
  and the iteration goes on.
- A branch with no upstream is pushed with `-u`, and has an upstream afterwards.
- A remote whose hook rejects the push makes the run exit 1 with `Push failed in <repo>:`, and
  the workspace remote is unchanged.
- With a repository at `./a` and one at `./a/b`, `./a/b` is pushed before `./a`.
- A text check: `prompts/build.md` contains `Never run \`git push\``, and contains no
  `git -C <toplevel> push`.

## 6. Accepted risks

- **A spec commit with no build commit stays local.** `commit_plan_specs` commits in a nested
  repository before the base is written, so that repository has not moved since the base. When no
  build commits there in the same cycle, the spec commit stays unpushed until a later cycle moves
  that repository. The workspace keeps its unconditional push, so its spec commits are not
  affected.
- **A repository the agent detached and never re-attached** is skipped with a message, not
  pushed. The prompt's branch rule makes that rare.
- **An agent that pushes anyway** breaks `skip_push`. The prompt forbids it, and the next push by
  Ralph is then a no-op.

## 7. Out of scope

- Pushing in plan, review or retro. They still never push.
- Pushing tags.
- Force pushes or any recovery from a rejected push.
- Choosing a remote other than `origin`.
