# Plan Commits Specs

`plan` records decisions in `specs/`. This spec makes Ralph commit those changes at the end of
each plan run, in one commit per repository. Plan never pushes. The planner edits specs but never
runs `git commit`.

## 1. Problem

`prompts/plan.md` tells the planner to write under `specs/` in two cases:

- **An unresolved decision.** "Choose the safer option and record the decision in the relevant
  spec." This edits an existing spec.
- **Work no spec covers.** "Author one at `specs/FILENAME.md`." This adds a spec.

Before this spec, nothing committed those changes. They stayed in the working tree when the plan
ended, so:

- The first build pass inherited a dirty `specs/`. It left the changes uncommitted, or folded them
  into a commit for an unrelated item, because build stages paths by name and nothing forbade it
  from staging a spec it did not change.
- The decision left no commit of its own. In a run whose goal is one feature spec from a DAG of
  features, nothing in the history showed that a later feature changed an earlier feature's
  decision.

### Revision

The first version of this spec made the planner commit its own spec changes, in a "Commit spec
changes" phase of `prompts/plan.md`, and made Ralph fail the pass with exit 1 when `specs/` was
still dirty afterwards. In practice the planner skips that phase: it records a decision, writes
the plan, reports, and stops. Every pass that records a decision then fails, and `auto` stops at
phase 3. A step the run depends on cannot rest on the model remembering it, so Ralph now makes the
commit itself. The planner keeps the freedom to create and edit specs.

## 2. Rule

A plan pass may create a file under `specs/` and edit one. It may not delete, rename or move one,
because `specs/` is the decision record. It runs no `git commit`, `git add` or other command that
moves `HEAD` or changes the index, in any repository.

At the end of the plan run, Ralph commits every change under `specs/`, in each repository that has
one, in one commit per repository. `specs/` means that directory at any depth:
`specs/features/03-foo.md` is under it. The plan precondition guarantees `specs/` was clean when
the run started, so every change Ralph commits is the planner's.

A commit cannot span repositories. In a meta workspace each repository gets its own commit, and a
nested repository that is a submodule of the workspace gets a second commit in the workspace that
bumps its gitlink. A nested repository may be a submodule or an independent clone that the
workspace ignores; `repo_state` finds both. Only a submodule gets the gitlink bump.

## 3. Behaviour

### Plan prompt

`prompts/plan.md` drops its commit phase. In its place it states:

- You may create a spec and edit a spec. Never delete, rename or move a spec.
- Never run `git add`, `git commit`, or any other command that changes the index or moves `HEAD`.
  Ralph commits your spec changes when the run ends.

Three existing lines change to match:

- The opening line "You do not implement anything" drops any mention of committing.
- The constraint "Plan only. Commit spec changes and nothing else." becomes "Plan only. Edit specs
  and the plan, and commit nothing."
- The "Unresolved decisions" rule to record a decision in the relevant spec drops "then commit
  it".

A project-local `PROMPT_plan.md` made under the first version of this spec still tells the planner
to commit. Its commits now fail the run (see "Guard after each plan pass"), and the error names the
local prompt.

### Preconditions before plan

Both checks are hard stops in `cmd_loop`'s plan branch, directly after `require_fresh_cycle` and
before `resolve_backend`, so neither `-n` nor `--dry-run` bypasses them. Each leaves every file
unchanged, prints to stderr and exits 1.

**Clean `specs/`.** Unchanged from the first version. `plan` refuses to start when any repository
in `repo_state` has an uncommitted change under its `specs/`, whether staged, unstaged or
untracked. Otherwise Ralph cannot tell an operator's edit from the planner's, and commits the
operator's edit under its own message. The check is the shared predicate `have_dirty_specs`,
which prints the first line of `dirty_spec_repos`. That helper lists every repository in
`repo_state` order whose `git status --porcelain -- specs` is non-empty.

```
Error: specs/ has uncommitted changes in <repo>.
Commit or stash them before running 'ralph plan'; plan commits its own spec changes.
```

**No detached `HEAD`.** `plan` refuses to start when a repository in `repo_state` that has a
`specs/` directory is on a detached `HEAD`, checked with `git -C <repo> symbolic-ref -q HEAD`.
Ralph never creates a branch on the operator's behalf, and failing before the run is cheaper than
failing after the planner's work. A repository without `specs/` is not checked, so a meta workspace
whose other submodules sit detached still plans. The check is one shared predicate,
`have_detached_spec_repo`, which prints the first failing repository.

```
Error: <repo> is on a detached HEAD.
Check out a branch before running 'ralph plan'; plan commits its spec changes there.
```

`<repo>` is the first repository that fails, as `repo_state` lists it.

### Guard after each plan pass

Ralph takes `repo_state` before and after each plan pass. The pass fails when either holds:

- **`HEAD` moved.** Any repository's entry differs between the two listings, or a repository
  appears that was absent before. The planner commits nothing, so any new commit is a violation.
- **A spec was deleted or moved.** `git -C <repo> status --porcelain --no-renames -- specs` lists a
  deletion, staged or unstaged, in any repository.

On failure Ralph prints to stderr and exits 1, without undoing any commit or restoring any file.
It commits nothing: the working tree no longer holds only the planner's permitted changes.

```
Error: plan pass <N> committed in <repo>; plan may not commit, Ralph commits its spec changes.
Error: plan pass <N> deleted <path> in <repo>; plan may not delete or move a spec.
```

When the first check fails and `resolve_prompt` chose a project-local `PROMPT_plan.md`, Ralph adds
a second line, because a local copy made under the first version of this spec still has a commit
step:

```
This project has its own PROMPT_plan.md; remove its commit step, or delete it and run 'ralph init --prompts'.
```

The plan convergence check is unchanged: `plan_state_hash` reads the working tree, so the commit
Ralph makes at the end of the run never affects it.

### Commit at the end of the run

Ralph commits once, when the plan run ends. It runs on every end of the run:

- the run converged;
- the run reached its iteration cap;
- the backend failed and the loop exited non-zero;
- the operator interrupted it with `SIGINT` or `SIGTERM`.

It does not run when the run never started a pass, because a precondition failed, nor when the
guard after a pass failed. In both cases `specs/` is left as it is.

A backend failure or an interrupt ends the run before the guard checks the last pass. So the
commit step first runs both guard checks against that pass: `HEAD` moved, and a spec deleted or
moved. When either fails, Ralph prints the guard's error, commits nothing, and leaves `specs/` as
it is.

For each repository `dirty_spec_repos` lists, in `repo_state` order:

1. Stage `specs/` with `git -C <repo> add -A -- specs`. The guard checks have already rejected
   deletions, so this stages only additions and edits.
2. Commit with `git -C <repo> commit --only -- specs`, so the commit holds `specs/` and nothing
   else. A path outside `specs/` that the operator or the planner staged stays staged and
   uncommitted. The commit is signed when the operator's git config sets `commit.gpgsign`. Ralph
   passes no `-S` and no `--no-gpg-sign`. The message is:

   ```
   docs(specs): record plan decisions

   - A specs/new-spec.md
   - M specs/features/03-foo.md
   ```

   The body lists every staged path under `specs/` with its
   `git diff --cached --name-status -- specs` letter, relative to the repository root, at most three
   lines. When more than three paths are staged, the first two are listed and the third line reads
   `- and N more`.
3. When the repository is nested and `git status --porcelain -- <path>` in the workspace lists it
   as modified, stage that path in the workspace and commit it with the subject
   `chore: bump <path> to <short sha>`.

A commit that fails, for example on a signing error, prints git's output to stderr and ends the run
with exit 1. Ralph leaves the remaining repositories uncommitted and the index as it is.

When the run ends with no change under `specs/`, Ralph commits nothing and prints nothing.

### No push

Plan never pushes. Ralph's spec commits stay local until the first build iteration: Ralph pushes
the workspace after each build iteration, and the build agent pushes each nested repository it
commits in. The per-pass push the first version of this spec added to plan is removed, so
`--skip-push` has no effect on `plan`.

### `--dry-run`

Under `--dry-run` no pass changes a file, so no repository has a spec change to commit. Plan prints
no push line.

### `auto`

The phase 3 guard in `cmd_auto` keeps its dirty-`specs/` refusal, which writes the state file at
phase 3 so that `--resume` retries the plan once the operator has committed. It gains the detached
`HEAD` check beside it, with the same state file and its own hint:

```
Error: <repo> is on a detached HEAD.
Check out a branch, then run 'ralph auto --resume'.
```

The stale-base check still runs first. Because the plan child now commits on every end of its run,
a dirty `specs/` at phase 3 means the operator edited a spec, or a plan child failed its guard.

## 4. Documentation

- `CLAUDE.md` and `AGENTS.md`: step 6 of the core loop flow says plan never pushes. Step 7 says
  plan commits nothing itself and Ralph commits its spec changes when the run ends. The hard-precondition paragraph names the detached `HEAD` check. The
  paragraph on `auto`'s phase guards names it too.
- `README.md` "Commit style": Ralph commits the planner's spec changes as one `docs(specs)` commit
  per repository.
- `docs/plan-format.md`: the precondition paragraph states the detached `HEAD` rule.
- `--skip-push`: the help text in `ralph` and the `README.md` options row say it covers build
  only.
- `docs/meta-repositories.md`: Ralph commits spec changes in each nested repository and bumps the
  gitlink of a submodule. Build pushes them.
- Code comments in `ralph` that say plan commits its own specs or pushes are
  corrected: at `mode_converges_on_plan`, `plan_state_hash`, the per-iteration snapshot, the push
  and the early exit.

## 5. Testing

### Preconditions before plan

- `plan -g` fails with the clean-`specs/` error when `specs/` holds an unstaged edit, a staged edit,
  or an untracked file, and leaves the working tree unchanged. The same holds for
  `specs/features/x.md` and for a nested repository's `specs/`.
- `plan -g` fails with the detached-`HEAD` error when the workspace, or a nested repository with a
  `specs/` directory, is detached.
- `plan -g` runs when a nested repository without `specs/` is detached.
- `plan --dry-run` and `plan -n 1` fail both checks the same way.

### Guard after each plan pass

Each test uses a mock backend that makes the stated changes.

- A pass that commits anything, including a spec, fails with the commit error and Ralph makes no
  commit of its own.
- With a project-local `PROMPT_plan.md`, that failure also prints the local-prompt line. Without
  one, it does not.
- A pass that deletes or renames a spec fails with the deletion error, and Ralph makes no commit.

### Commit at the end of the run

- A run whose pass adds `specs/new.md` and edits `specs/features/03-foo.md` ends with exactly one new
  commit, whose subject is `docs(specs): record plan decisions` and whose body lists both paths
  with `A` and `M`. Nothing is pushed.
- A run of two passes that both change specs, then converges, ends with exactly one new commit.
- A run that changes no spec makes no commit.
- A run whose backend fails after editing a spec ends with that spec committed and exits non-zero.
- A run interrupted after editing a spec ends with that spec committed.
- In a meta workspace, a pass that edits a spec in a nested submodule ends with one commit in that
  repository, one `chore: bump` commit in the workspace, and nothing pushed.
- A file outside `specs/` that the planner left dirty is not committed.
- A failing commit, simulated with a `pre-commit` hook that exits 1, ends the run with exit 1 and
  leaves `specs/` dirty.

### `auto`

- `auto` with a dirty `specs/` runs phases 1 and 2, refuses at phase 3, starts no plan child, and
  writes the state file at phase 3.
- `auto` with a detached spec repository refuses the same way, with its own hint.
- After the operator fixes either, `auto --resume` starts the plan child.

## 6. Accepted risks

- **Ralph commits the planner's mistakes.** The commit checks where a change lands, not whether
  its content is right. A bad decision recorded in a spec is committed, and build pushes it.
  Review reads the anchor set as the standard, so a wrong spec clause becomes the standard.
- **An interrupt can commit a half-written spec.** A Ctrl-C during the planner's write leaves a
  partial file, and Ralph commits it. The history shows it, and the next plan run can repair it.
- **One commit per run hides the order of decisions.** The commit message does not say what was
  decided, only which files changed. The diff carries the decision.
- **A new spec must be committed before planning.** The operator commits a spec before planning
  against it, because the precondition cannot tell an operator's draft from the planner's edit.
- **Uncommitted edits outside `specs/` go unseen.** The guard checks commits and deletions under
  `specs/`, so a planner that edits another file and leaves it uncommitted passes, and Ralph does
  not commit that file.
- **A new `specs/` in a detached repository fails late.** The detached-`HEAD` check skips a
  repository without `specs/`. A planner that creates the first spec in such a repository makes
  Ralph's commit land on a detached `HEAD`. Ralph commits it there, where it is easy to lose.
- **A nested spec commit can stay unpushed.** Build pushes only the nested repositories it commits
  in. A spec commit in a nested repository that build never touches stays local, and the
  workspace push publishes a `chore: bump` that points at it. A clone of the workspace then cannot
  check out that submodule until the operator pushes it.
- **Re-planning mid-cycle puts spec commits in the cycle's work.** A `plan` run after build has
  written `.ralph/cycle-base`, for example to replace a `[~]` item, commits after the base. Review
  then counts those spec diffs as changed files and may file text findings against them.
- **A guard failure leaves the tree for the operator.** Ralph neither commits nor restores after a
  failed guard, and does not rewrite history. The operator reverts a rejected commit and restores a
  deleted spec.

## 7. Out of scope

- A commit message that names the decision. Ralph cannot know it, and the planner may not commit.
- Creating a branch on a detached `HEAD`. Ralph refuses instead.
- Splitting a spec into features. The operator does it outside Ralph, so plan never moves a spec.
- A convention for where a new spec goes, such as `specs/features/`. Plan writes the new spec where
  the goal points or at the top of `specs/`.
- Any change to build or review. Both still never edit `specs/`.
