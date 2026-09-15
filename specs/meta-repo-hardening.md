# Meta Repository Hardening

Ralph serves two workspace shapes. The first is a standalone service repository: one `.git`, one
remote, the agent commits where it stands. The second is a meta repository: a workspace repository
that holds a sync script and a manifest, clones each service into a gitignored directory such as
`source/`, and carries no service code of its own. `specs/nested-git-repos.md` made the build noop
exit correct for the second shape by watching every repository beneath the workspace. It changed the
change verdict and nothing else, and its §7 lists what it left alone: the push block and the
prompts.

This spec closes the gaps that an audit of that work found on 2026-09-15, each reproduced against a
throwaway workspace with a mock backend:

- **The workspace push kills a meta-repo build.** A meta repository often has no `origin`. The agent
  commits in `source/svc`, ralph then runs `git push origin main` on the workspace, git says
  `'origin' does not appear to be a git repository`, and the loop exits 1 after iteration 1.
- **Symlinked checkouts are invisible.** `repo_state` scans with `find .`, which does not follow
  symlinks, so a `source -> /shared/checkouts` link hides every clone and the run stops at iteration
  2 with the bug the nested spec fixed.
- **The agent is never told where to commit.** From the workspace root `git status` shows nothing
  inside a gitignored clone, and `git add source/svc/f.txt` exits 0 and stages nothing — with or
  without `-f`, ignored or not. `prompts/build.md` says "commit" and "`git push`" unqualified and
  delegates the git commands to wherever the agent happens to stand.
- **Detached and submodule checkouts strand the work.** A sync script that pins a sha, and
  `git submodule update`, both leave the clone detached; a commit there is detected but `git push`
  fails with `No configured push destination`. A commit in a real submodule leaves the superproject
  with ` M source/svc` and nothing bumps the pointer, so a fresh clone checks out the old sha.
- **Nested clones may be outside `safe.directory`.** The container trusts `/workspace` and only
  that. A clone owned by another uid fails every git command with `dubious ownership`, and
  `repo_state` records a constant `-` for it.
- **A commitless workspace aborts the loop.** `head_before=$(git rev-parse HEAD)` uses the plain
  form the nested spec forbids for nested repositories, so a workspace with no commit dies with a
  raw `fatal: ambiguous argument 'HEAD'` and exit 128.

The standalone shape must not regress. Every change below reduces to today's behaviour when the
listing holds one entry, the workspace has an `origin`, and `HEAD` resolves.

## 1. Model

Three rules, one per layer:

1. **Ralph watches what it can reach.** Discovery follows symlinks, because a symlinked checkout is a
   repository the agent can commit into, and the verdict must see every such repository.
2. **Ralph pushes what it can push.** A workspace with no `origin` or no commit has nothing for the
   push block to do. That is a fact about the workspace, not a failure, so the block skips and says
   so. A push that git *rejects* is still a failure.
3. **The agent commits where the file lives.** `prompts/build.md` carries the git instructions
   itself: resolve the repository that owns each changed path, run every git command inside it, and
   shape the commits as Conventional Commits. Ralph itself pushes nothing nested; pushing a nested
   repository is the agent's step, and the prompt now states it.

The over-detection bias of `specs/nested-git-repos.md` §3 stands: every rule here that could err
errs towards seeing a change, never towards missing one.

## 2. Discovery follows symlinks

`repo_state` scans with `find -L`:

```sh
find -L . -maxdepth 6 -name .git -prune -print 2>/dev/null
```

`-L` makes `find` follow a symlink to a directory and descend into it, so `source -> /shared/checkouts`
is scanned as if the clones sat under `source/`. The emitted paths keep the link's own name
(`./source/svc`), so the listing is unchanged for a workspace where `source/` is a real directory.
`plan_state_hash` already uses `find -L specs` for the same reason; the two scans now agree.

Three properties were verified on GNU findutils 4.10.0, which the `node:20` image ships, and on
bfs 4.1.1, which NixOS may install as `find`:

- **A true loop is skipped, not walked.** `self -> .` produces a `File system loop detected`
  diagnostic on stderr, which `2>/dev/null` discards, and `find` does not descend. `-maxdepth 6`
  bounds the walk regardless.
- **A link out of the workspace is followed.** `source/loop -> ..` listed every sibling directory's
  repositories to the depth bound. This is accepted. The realistic symlinked checkout is *also*
  outside the workspace — that is why it is a symlink — so "inside the workspace" is not a usable
  filter, and `find` has no portable expression for "follow this link but not that one". The bound
  is on depth, not breadth: a link to `$HOME` or `/` costs a slow scan and a listing that other
  people's commits can move, which delays the noop exit by the over-detection rule. That is a
  misconfigured workspace, and §8 names it.
- **`-name .git -prune` behaves as before.** A `.git` directory reached through a link is still
  pruned; a `.git` file is still printed. Section 3 of the nested spec applies unchanged.

The `plan converges while a nested repository moves` and `review converges` cases hold: plan and
review still read `plan_state_hash` and ignore the listing.

## 3. The push block skips what it cannot push

Before `git push origin "$current_branch"`, the build push block checks two facts about the
workspace, in this order, and skips the push with one line on stdout when either fails:

| Condition | Line |
|-----------|------|
| `git remote get-url origin` fails | `No 'origin' remote — skipping push.` |
| `git rev-parse -q --verify HEAD` fails | `No commit on the workspace branch — skipping push.` |

Both are evaluated every iteration against the workspace as it stands, not once per run: the first
iteration of a fresh meta repository may be the one that adds the remote or makes the first commit.

A push that reaches git and is rejected — a diverged branch, a missing credential, a rejected hook —
still prints `Push failed:` with git's output and exits 1. The `has no upstream branch` recovery is
unchanged. Skipping is for the two conditions above and nothing else: a missing remote is not a
rejected push, and folding it into the failure path is what stops a meta-repo build at iteration 1.

`--skip-push` keeps its meaning. It is the operator's choice not to push; the skip lines record a
fact about the workspace. Under `--skip-push` neither check runs and neither line prints. Under
`--dry-run` the block prints `[dry-run] Would run: git push origin <branch>` as it does today; a dry
run inspects no remote.

The metrics record is unchanged. `commits`, `files_changed`, `insertions` and `deletions` stay
derived from the workspace `HEAD` pair, and a skipped push writes nothing to `metrics.jsonl`.

## 4. The workspace `HEAD` snapshot tolerates a commitless workspace

`head_before` and the metrics `head_after_m` are taken with the form the nested spec requires:

```sh
head_before=$(git rev-parse -q --verify HEAD 2>/dev/null || echo -)
```

`repo_state` already records `-` for a commitless repository, and the workspace is one entry in that
listing, so the two snapshots now use one convention. `write_iteration_metrics` needs no change: it
compares the pair as strings, `git rev-list --count -..<sha>` fails into the existing `|| echo 0`,
and `git diff --shortstat` fails into the existing `|| true`. A first commit on the workspace flips
`-` to a sha and records `noop: false` with `commits: 0`, which is the same understatement §4 of the
nested spec accepts for nested-only iterations.

`git branch --show-current` prints the unborn branch's name (`main` or `master`), so `current_branch`
and the metrics directory name are unaffected.

## 5. The agents commit where the file lives

`specs/nested-git-repos.md` §9 kept the prompts out of scope. This spec brings two files in:
`prompts/build.md` and `prompts/review.md`. `prompts/plan.md` is unchanged: its `Files` field
already lists paths relative to the workspace root, and a path under `source/svc/` names its
repository.

### `prompts/build.md` carries its own git instructions

Phase 4 step 3 today states the message and staging rules but says nothing about which repository a
commit belongs to, so it reads the same in a standalone repository and in a meta repository. That
step is replaced. The build prompt states the whole git procedure, in two rule blocks, so that every
backend follows one procedure from one file in either layout.

**Where to commit** — the repository rules:

- Every changed path belongs to one repository: the one `git -C <dir> rev-parse --show-toplevel`
  prints for the path's directory. Group the changed paths by that repository before running any
  other git command.
- Run every git command for a group with `-C <toplevel>`. A bare `git status` from the workspace
  root shows nothing inside a gitignored nested repository, and a bare `git add` of a path inside a
  nested repository **exits 0 and stages nothing** — with or without `-f`, ignored or not (verified
  on git 2.51). The mistake is silent, so the next rule catches it.
- After staging, `git -C <toplevel> diff --staged --stat` must list every path in the group. An
  empty staged diff means the paths belong to another repository. Resolve again. Never retry with
  `-f`, `-A` or `.`.
- **Never `git add -A` or `git add .`**, in any repository, for any diff. From a meta repository
  root they stage a nested repository itself as a gitlink (`warning: adding embedded git
  repository`), and a commit of that pointer breaks every clone of the workspace.
- An item whose paths span two repositories produces one set of commits per repository.
- **Never commit on a detached `HEAD`.** Check `git -C <toplevel> symbolic-ref -q HEAD` first. When
  it fails, check out a branch before committing: the branch `AGENTS.md` or `CLAUDE.md` names for
  that repository when one is named, otherwise a new branch `ralph/<item-title-in-kebab-case>`
  created at the current commit. Record the branch in the `PROGRESS.md` entry.
- After committing in a nested repository, run `git status --short -- <path>` in the workspace. A
  ` M <path>` line means the repository is a submodule of the workspace. Stage that path and commit
  the pointer update in the workspace with the subject `chore: bump <path> to <short sha>`.
- Push every repository you committed in, from inside it: `git -C <toplevel> push`, with
  `-u origin <branch>` on a branch you created. Ralph pushes the workspace and only the workspace.

**How to commit** — the message and staging rules, which step 3 already carries and this block
collects unchanged, except where a rule below names a repository:

- Follow [Conventional Commits](https://www.conventionalcommits.org/): `<type>(<scope>): <subject>`.
  Types are `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`. Mark
  a breaking change with `!` after the type or scope.
- Subject in the imperative mood, lowercase, at most 50 characters, no trailing period. Scope is
  optional, lowercase, and names the affected area.
- Body optional, at most 3 bulleted lines, only when the subject alone does not explain the change.
- One logical change per commit. Separable concerns within the item — a refactor and the feature it
  enables, tests that stand alone — become separate commits, in dependency order.
- Stage with explicit paths: `git -C <toplevel> add -- <paths>`.
- Match the repository's prevailing style: read `git -C <toplevel> log --oneline -10` first.
- Never stage `IMPLEMENTATION_PLAN.md`, `PROGRESS.md`, `PROMPT_*.md` or `.ralph/`. They live in the
  workspace and are local to the loop.
- Write the message through a heredoc so the subject, body and footer keep their newlines.

Step 4, today the bare word `git push`, becomes "Push as **Where to commit** states."

The two blocks are prose the build agent reads on every iteration, so they cost prompt tokens on
every backend. They are kept to the rules above and nothing else: no examples, no type table beyond
the list, no rationale. The rationale lives here.

### `prompts/review.md`

The evidence sentence in Phase 2, "Evidence comes from the tree, the test suite, `git log`,
`git diff`, and `PROGRESS.md`", gains one sentence: "Run `git log` and `git diff` inside the
repository that owns the item's `Files`; a path under a nested repository names that repository, and
the workspace log does not show its commits."

Review's own rules are otherwise untouched. It still never commits, never pushes, and never reads
`specs/`.

## 6. The container trusts every repository under the workspace

`container/devcontainer.json`'s `postStartCommand` sets `safe.directory` to `*` instead of
`/workspace`:

```sh
git config --global --add safe.directory '*'
```

`updateRemoteUserUID` makes the container user match the host uid, so the workspace itself is
normally trusted without this. A clone that arrives with another uid — a sync script that runs
`docker run` through the mounted socket, or one invoked with `sudo` — is not, and git then refuses
every command in it, including the agent's commit and `repo_state`'s `rev-parse`. `*` trusts every
repository the container can see, which is the correct trust boundary inside an isolated container.

The `/workspace/*` glob form was rejected: git accepts a trailing `/*` only from 2.46, and the
`node:20` image ships 2.39.5 (verified). `*` is honoured from 2.35.3.

## 7. Documentation

- **`README.md`** gains a short section, **Meta repositories**, under **Project artifacts**: what
  ralph watches (every repository beneath the workspace, through symlinks), what it pushes (the
  workspace only, skipping when there is no `origin`), and what the agent does (commits and pushes
  inside the repository that owns each file). It tells the operator to write the workspace's
  `CLAUDE.md` or `AGENTS.md` so it names each service's own conventions file and, where the sync
  script pins shas, the branch the agent should commit on.
- **`README.md` Troubleshooting** gains two entries. *Build stops early in a meta repository*: check
  `--skip-push` was not passed by habit, and that `source/` is not deeper than depth 6. *Build never
  exits early*: a test suite that creates git repositories under the project tree reads as progress
  on every iteration; write fixtures under `$TMPDIR` (§8).
- **`CLAUDE.md` and `AGENTS.md`**: the loop-flow step that reads "push changes after each iteration"
  becomes "push the workspace after each iteration, skipping when it has no `origin` or no commit".
  The nested-repository sentence added by the previous spec stands.

## 8. What this does not fix

**Transient repositories defeat the noop exit.** Any `.git` that appears or vanishes between the two
snapshots is a change, and a test suite that `git init`s a fixture under the project tree does that
on every iteration, so the exit never fires and the run reaches its cap. Reproduced: an idle mock
that only created `tmp/fixture-$RANDOM` ran four iterations instead of two. This is the failure mode
§3 of the nested spec rejects dirty-worktree tracking for, arriving by another path. It is accepted
here because every fix costs more than the defect: ignoring appearances breaks the sync-script case
the nested spec exists for; an ignore list is the configuration that spec rejected; and a commitless
filter does not distinguish a fixture from a fresh clone once the fixture commits. The cap bounds the
cost — `calculate_build_iterations` grants `ceil(open × 1.2)` — and only a `-n` run pays in full.
§7 documents the workaround.

**Ralph does not warn about unpushed nested commits.** §5 tells the agent to push; nothing checks that
it did. `specs/nested-git-repos.md` §7 accepted this and it stands.

**A directory of clones that is not itself a repository is refused.** `cmd_loop` requires
`git rev-parse --is-inside-work-tree` and the meta repository is one by definition: it holds the
sync script and the manifest. A plain directory gets `not inside a git repository. Run 'git init'
first`, which is the right instruction.

**A symlink to a large tree is scanned.** §2 accepts the cost and the over-detection.

**`cmd_sandbox` calls a linked worktree a submodule.** A workspace whose `.git` is a file is refused
with a message about submodules; a `git worktree add` checkout has the same shape and an absolute
`gitdir:` pointer that also cannot resolve in the container. The refusal is right and the wording is
wrong. It is one string and belongs to the sandbox, not to this spec.

## 9. Testing

Change detection and the push block are tested with mock backends in `test/nested_repos.bats` and
`test/pipeline.bats`, following the existing `create_scripted_backend` idiom. `--dry-run` cannot
exercise any of them.

- A commit in a nested repository reached through a symlinked directory prevents the 2-noop exit.
  The link target sits outside the workspace, in a sibling temp directory.
- A workspace containing a symlink loop (`self -> .`) completes a build with no error and exits after
  two noops.
- A build in a workspace with no `origin` and a nested committing mock, **without** `--skip-push`,
  exits 0, prints `No 'origin' remote — skipping push.` once per iteration, and never prints
  `Push failed`.
- A build in a workspace with a bare `origin` still pushes; the remote's branch moves. This pins the
  skip to the missing-remote case.
- A build in a workspace with an `origin` that rejects the push still prints `Push failed:` and exits
  1. Existing behaviour, pinned so the skip cannot widen into it.
- Under `--skip-push` neither skip line prints, in a workspace with no `origin`.
- A build in a workspace with zero commits and an idle mock exits 0 after two noops. Metrics record
  `commits: 0` and `noop: true` for both iterations.
- A build in a workspace with zero commits whose mock makes the first workspace commit records
  `noop: false` for that iteration and does not exit early on it.
- A commitless workspace with an `origin` prints `No commit on the workspace branch — skipping push.`
  and does not exit 1.
- `container/devcontainer.json`'s `postStartCommand` contains `safe.directory '*'` and no longer
  contains `safe.directory /workspace`, asserted by grep in `test/sandbox.bats`.
- Every existing case in `test/nested_repos.bats`, `test/pipeline.bats`, `test/metrics.bats` and
  `test/review.bats` passes unchanged.

The prompt changes have no BATS coverage, by the repository's convention that no test asserts
prose. Each plan item that edits `prompts/build.md` or `prompts/review.md` carries a `grep -c`
criterion on a phrase it adds — `Where to commit`, `How to commit`, `repository that owns the
item's` — in its `Done when`.

## 10. Out of scope

- Pushing nested repositories from ralph, and any per-repository remote, branch or upstream handling.
- Warning about nested commits that were never pushed.
- Excluding transient repositories from the verdict, by pattern, configuration or heuristic.
- Aggregate git counts across repositories in `metrics.jsonl`.
- Reading `repos.json`, running the sync script, or any awareness of how clones arrived.
- Following symlinks selectively, or refusing links that leave the workspace.
- Changes to `prompts/plan.md`, `cmd_archive`, `cmd_init`, `cmd_auto` or the sandbox's submodule
  refusal wording.
- Any change to how plan and review converge.

## 11. Follow-ups

**Warn about unpushed nested commits.** For each nested entry whose `HEAD` moved during an iteration,
`git -C <repo> rev-list --count @{upstream}..HEAD` says whether the agent pushed. A one-line warning
per repository closes the gap §5 leaves to the prompt, at the cost of a per-repository upstream
query and a rule for repositories with no upstream at all.

**Fix the sandbox's worktree wording.** Distinguish `gitdir: ../` (submodule, relative) from an
absolute `gitdir:` (linked worktree) in `cmd_sandbox` and name each correctly.

**Exclude transient repositories.** If §8's accepted loss proves costly, the smallest honest fix is
to ignore a repository that is present in `state_after` and absent from `state_before` **only when**
it is also absent from the *next* iteration's `state_before` — a repository that lives for one
iteration was a fixture. That needs a three-snapshot window and a rule for the last iteration, and is
worth specifying on its own terms.
