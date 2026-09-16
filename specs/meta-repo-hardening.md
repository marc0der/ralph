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
`prompts/build.md` and `prompts/review.md`. `prompts/plan.md` is unchanged except as §12 states:
its `Files` field lists paths relative to the workspace root, and a path under `source/svc/` names
its repository.

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
- Changes to `prompts/plan.md` or `cmd_auto` except as §12 states, and changes to `cmd_archive`,
  `cmd_init` or the sandbox's submodule refusal wording.
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

## 12. Addendum: the artifacts live at the workspace root

Added 2026-09-15 after the runs of 2026-09-11 in a meta repository put `IMPLEMENTATION_PLAN.md`
under a node directory. §10 excluded changes to `prompts/plan.md` and to `cmd_auto`. This addendum
reopens both, only as far as the sections below state, and it settles which modes take a goal. How
plan and review converge stays out of scope.

### The failure

The operator runs `ralph plan -g <path>` where the path names one specification deep in the tree,
such as `citc/svc/features/FT-008.md`. That is one normal way to run ralph in a meta repository: this
specification belongs to one service, so it lives beside or inside that service's clone, not under
the workspace's own `specs/`. The node directory the path passes through carries its own `AGENTS.md`,
`specs/`, `docs/` and `source/`, so it looks exactly like a project root.

The bundled prompts name every artifact by a bare relative path: read `AGENTS.md`, read `specs/`,
read `IMPLEMENTATION_PLAN.md` "if present", create or update `IMPLEMENTATION_PLAN.md`. Nothing anchors
those paths. The agent resolved all of them against the node the goal named, ran
`ls IMPLEMENTATION_PLAN.md` there, found nothing, and wrote a new plan at
`citc/svc/IMPLEMENTATION_PLAN.md`. It never listed the workspace root. Two plan runs did this on the
same afternoon; each spent several minutes and wrote a complete plan in the wrong place.

Ralph then hid the failure. `plan_state_hash` fingerprints the root `IMPLEMENTATION_PLAN.md` and the
root `specs/`, so the pass changed neither, the metrics recorded `noop: true`, and the loop printed
`Plan converged — pass 1 changed nothing. Exiting early.` after one iteration. The operator saw a
converged plan and an empty root file.

The operator's workaround was one line at the top of a project-local `PROMPT_plan.md`: "This is a
meta-repo. Place your IMPLEMENTATION_PLAN.md and PROGRESS.md in this base directory." The next run
edited the root plan on all five iterations. The line works, but it is a per-project patch to a
scaffolded copy that also overrides every later fix to the bundled prompt, and it exists for plan
only.

### Model

Ralph knows where the root is. It runs in that directory, it scaffolds the artifacts there, and
`require_init_artifacts` checks for the plan there — and, in build and review, the progress log —
before the first iteration. Asking the model to infer the same fact from relative paths is the
defect. One rule replaces the inference: **ralph names the root in the prompt.** The prompts state
the absolute path of the two artifacts, and ralph substitutes it, the way it already substitutes
`{{GOAL}}`.

The anchor covers `IMPLEMENTATION_PLAN.md` and `PROGRESS.md` and nothing else. **`specs/` stays
unanchored.** In a meta repository a specification sits in one of two places. A feature that belongs
to one service is specified inside that service's repository. A feature that spans several nodes is
specified in the workspace's own `specs/`. Both places are legitimate and the goal names the one to
plan against, so neither is the location to anchor: anchoring `specs/` to the root would tell the
agent to ignore a specification inside a service, and anchoring it to the goal's node would hide a
cross-node specification. The same holds for `AGENTS.md` and `CLAUDE.md`: a node's own guardrails are
the ones the agent must read when it works in that node.

No runtime check backs the rule. A scan for a stray artifact after each pass was considered and
dropped: it adds a failure path for a defect the prompt removes at its source. The failure it would
guard against is silent, and stays silent. `convergence_message` prints one line for a plan of
thirty items and for an empty one, so a pass that ignores the anchor looks exactly like a pass that
converged honestly, and the operator learns of it at the next `ralph build`. That loss is accepted
here and recorded below.

### The `{{WORKSPACE}}` substitution

`cmd_loop` expands a second placeholder beside `{{GOAL}}`, with the same bash parameter expansion.
`{{GOAL}}` expands first and `{{WORKSPACE}}` second, which is the order the two lines already sit
in. The order is intended, not incidental: it lets a goal carry the placeholder, so
`-g 'plan the work in {{WORKSPACE}}/specs/x.md'` reaches the agent with a real path. The replacement
is quoted:

```sh
prompt="${prompt//\{\{WORKSPACE\}\}/"$PWD"}"
```

The quotes are load-bearing. `patsub_replacement` is on by default from bash 5.2, and the `node:20`
image ships 5.2, so an unquoted `&` in the replacement expands to the text the pattern matched: with
`PWD=/home/x&y/z` the unquoted form yields `/home/x{{WORKSPACE}}y/z` (verified on bash 5.3.9). The
existing `{{GOAL}}` expansion carries the same defect today — `-g 'fix save & load'` reaches the
agent as `fix save {{GOAL}} load` — and is quoted the same way in the same edit.

`$PWD` is the directory ralph runs in, absolute, and it is the directory every other part of ralph
already treats as the root: `cmd_init` scaffolds there, `require_init_artifacts` reads there,
`plan_state_hash` hashes there. Inside the sandbox it is the container path, which is the path the
agent's tools see, so no translation is needed. A local `PROMPT_<mode>.md` that carries no
placeholder is unaffected, and `--dry-run` prints the expanded prompt, so the operator can read the
path ralph handed the agent. The dry-run label reads `with goal and workspace substituted`.

### The goal is required, and only `plan` takes one

The stray plan had a second cause. `plan` derives its work from the goal, but `-g` is optional and
`{{GOAL}}` falls back to `No specific goal provided`, so a bare `ralph plan` plans against whatever
`specs/` it resolves — nothing relevant, in a meta repository. `build` and `review` have the opposite
defect: they accept a goal that cannot change what they do, because their input is
`IMPLEMENTATION_PLAN.md`. Three rules settle both:

- **`plan` requires `-g`.** `cmd_loop` refuses a plan run with an empty goal:
  `Error: 'plan' requires a goal. Pass -g <specification or directory>.` The check runs beside
  `require_init_artifacts`, so neither `-n` nor `--dry-run` bypasses it. The
  `${goal:-No specific goal provided}` fallback is deleted with the last caller that needs it.
- **`build` and `review` reject `-g`.** They keep `g:` in the `getopt` spec and refuse the flag with
  a reason, the way `cmd_auto` already refuses `-n`:
  `Error: 'build' does not accept -g/--goal; the work comes from IMPLEMENTATION_PLAN.md.` A per-mode
  `getopt` spec was rejected: `mode` is known before `getopt` runs, so dropping `g:` is possible, but
  it yields a bare `invalid option -- 'g'` and states no reason.
- **`auto` requires `-g`** and forwards it to the `plan` phase alone. `child_flags` keeps `-m`, `-b`,
  `--skip-push`, `--no-metrics` and `-v` for every phase; `-g` leaves `child_flags` and joins the
  plan phase's own command line.

`prompts/build.md` and `prompts/review.md` lose their `## Goal` heading and their `{{GOAL}}` line:
the placeholder has no value left to take. `{{GOAL}}` stays in `prompts/plan.md`. The banner's
`Goal:` line already prints only when a goal is set, so it becomes a plan-only line with no change.

The usage text states the new shape: `-g, --goal TEXT` reads
`Goal to inject into the prompt template (plan and auto only; required)`.

### Prompt changes

The three bundled prompts change as follows, and in no other way:

- One paragraph above the `---` rule: under the `## Goal` block in `plan`, and where that block used
  to sit in `build` and `review`. "The workspace root is `{{WORKSPACE}}`. `IMPLEMENTATION_PLAN.md`
  and `PROGRESS.md` live at the root and nowhere else. Read and write no other copy. Every path
  written in `IMPLEMENTATION_PLAN.md` — `Spec:` and `Files` — is relative to the workspace root."
- The paragraph carries one further sentence, keyed to each mode's own input. `plan`: "The goal may
  name a specification or a directory anywhere beneath the root. When it does, also read the
  `AGENTS.md` or `CLAUDE.md` and the `specs/` of the repository that owns that path." `build` and
  `review` carry the same sentence keyed to the `Files` of the item in hand, because neither takes a
  goal.
- The Phase 1 bullets that read the plan and the progress log name
  `{{WORKSPACE}}/IMPLEMENTATION_PLAN.md` and `{{WORKSPACE}}/PROGRESS.md`. Each bullet keeps its own
  `(if present)` hedge: a plan run does not require `PROGRESS.md`.
- The sentence that creates or updates the plan — Phase 3 in plan and review, Phase 4 step 1 in
  build — names `{{WORKSPACE}}/IMPLEMENTATION_PLAN.md`. In build (Phase 4 step 2) and review (the
  **Record every supersession** rule) the sentence that appends the progress entry names
  `{{WORKSPACE}}/PROGRESS.md`; plan writes no progress entry.
- Build's Phase 2 `[~]` path writes both artifacts too. Its two steps name
  `{{WORKSPACE}}/IMPLEMENTATION_PLAN.md` and `{{WORKSPACE}}/PROGRESS.md`, because build takes that
  path while it stands inside the nested repository that contradicted the item.

Every other mention of the two files stays bare. Once the absolute path is stated where each file is
read and at every point a phase writes it, repeating it elsewhere costs tokens on every iteration and
buys nothing. The `specs/` bullet, the `AGENTS.md`/`CLAUDE.md` bullet, and the `Spec:` field's
`specs/file.md` example are untouched, per the model above.

`templates/IMPLEMENTATION_PLAN.md` and `templates/PROGRESS.md` are unchanged: they are the scaffolded
files, not prompts, and no placeholder is expanded in them.

### Documentation

- **`README.md` Meta repositories** gains one bullet: the artifacts live at the workspace root, the
  goal may name a specification anywhere beneath it — inside a service for a feature that belongs to
  one service, in the workspace's own `specs/` for one that spans several — and the prompts carry the
  root's absolute path.
- **`README.md`** states the goal rules wherever it shows a loop invocation: `plan` and `auto`
  require `-g`, and `build` and `review` refuse it. Every bare `ralph plan` example gains a goal.
- **`README.md` Troubleshooting** gains *Plan converged after one pass and the plan is empty*: an
  older prompt with no `{{WORKSPACE}}` anchor let the agent write the plan beside the specification;
  update the bundled prompts and delete or refresh any project-local `PROMPT_*.md`, which override
  them and go stale.
- **`CLAUDE.md` and `AGENTS.md`**: the loop-flow step that substitutes `{{GOAL}}` also names
  `{{WORKSPACE}}`, and records that `{{GOAL}}` now reaches `plan` alone. The command table's `plan`
  row states that the goal is required.

### Testing

`test/dry_run.bats` carries the expansion cases, beside its existing goal-substitution case:
`resolve_prompt` returns a path and substitutes nothing, so `test/resolve_prompt.bats` keeps path
resolution only. `test/validation.bats` carries the goal refusals and `test/auto.bats` the
forwarding, each with the existing mock idiom:

- A bundled prompt containing `{{WORKSPACE}}` under a mock `RALPH_CONFIG_DIR`, run with `--dry-run`,
  prints the absolute workspace path in place of the placeholder and prints no literal
  `{{WORKSPACE}}`.
- A local `PROMPT_plan.md` with no placeholder is passed through unchanged.
- A prompt that carries both placeholders expands both, and a goal that itself carries
  `{{WORKSPACE}}` has it expanded too, because `{{GOAL}}` expands first.
- A workspace path containing `&` reaches the prompt verbatim, and a goal containing `&` does too.
- `ralph plan` with no `-g` exits 1 with `'plan' requires a goal`, with `--dry-run` and with `-n 1`,
  and in a workspace whose artifacts are all present.
- `ralph build -g x` and `ralph review -g x` each exit 1 and name `IMPLEMENTATION_PLAN.md`.
- `ralph auto` with no `-g` exits 1. `ralph auto --dry-run -g "the goal"` shows `-g` on the plan
  phase's command line and on no other phase's, which replaces the current assertion in
  `test/auto.bats`.
- `prompts/build.md` and `prompts/review.md` contain no `{{GOAL}}`, asserted by `grep -c`.
- Every existing `plan` invocation in the suite gains a goal, and `test/dry_run.bats`'s goal
  substitution case moves from `build` to `plan`.
- Every existing case in `test/pipeline.bats` and `test/resolve_prompt.bats` passes unchanged.

The prompt edits carry a `grep -c '{{WORKSPACE}}'` criterion per file in their `Done when`, by the
convention §9 states.

### What this does not fix

**Convergence rests on the plan alone in a meta repository.** `plan_state_hash` hashes the root
`IMPLEMENTATION_PLAN.md` and the root `specs/`. The second half exists for the standalone shape,
where the plan agent may author a new `specs/FILENAME.md` for work no spec covers, and that pass
must not read as converged. In a meta repository half the input is out of reach. A cross-node
specification sits in the root `specs/`, so it is hashed and it does count towards convergence. A
specification inside a service sits wherever that service keeps it, and the goal names it. `specs/`
is a naming convention there, not a location ralph can rely on, so ralph does not look for a nested
`specs/` and hashes nothing outside the root. For that half, convergence is the plan file changing or
not, which is the output the loop exists to settle. A pass that edits only the nested specification
and leaves the plan alone reads as converged.

**A pass that ignores the anchor still reads as converged.** With no runtime scan, an agent that
writes the plan below the root despite the stated path produces the same silent `Plan converged`
line as before. The prompt change is the whole fix; if it proves insufficient on some backend, the
scan is the follow-up to specify.

**Stale project-local prompts stay stale.** `ralph init --prompts` scaffolds a copy that overrides
the bundled prompt for as long as it exists, and nothing warns when the bundled one moves on. The
2026-09-11 workspace ran a `PROMPT_build.md` that still invoked the removed commit skill and carried
none of §5. Warning about, or diffing, a scaffolded copy is worth its own item and is out of scope
here; the troubleshooting entry names the symptom.

### Out of scope

- Any change to `prompts/plan.md` beyond the prompt edits above.
- Anchoring `specs/`, `AGENTS.md` or `CLAUDE.md` to the root, for the reason the model states.
- Any runtime scan for, or refusal of, an artifact written below the root.
- Hashing a specification the goal names into `plan_state_hash`.
- Detecting or refreshing a stale project-local `PROMPT_*.md`.
- Any placeholder beyond `{{GOAL}}` and `{{WORKSPACE}}`.
