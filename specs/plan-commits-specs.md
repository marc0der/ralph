# Plan Commits Specs

`plan` records decisions in `specs/`, but it never commits them. This spec makes each plan pass
commit its own spec changes, lets Ralph push them, and makes Ralph enforce that a plan commit
touches `specs/` and nothing else.

## 1. Problem

`prompts/plan.md` tells the planner to write under `specs/` in two cases:

- **An unresolved decision.** "Choose the safer option and record the decision in the relevant
  spec." This edits an existing spec.
- **Work no spec covers.** "Author one at `specs/FILENAME.md`." This adds a spec.

The plan prompt says nothing about committing, and Ralph pushes only after a build pass. The spec
changes stay uncommitted in the working tree when the plan ends, so:

- The first build pass inherits a dirty `specs/`. It leaves the changes uncommitted, or folds them
  into a commit for an unrelated item, because build stages paths by name and nothing forbids it
  from staging a spec it did not change.
- The decision leaves no commit of its own. In a run whose goal is one feature spec from a DAG of
  features, nothing in the history shows that a later feature changed an earlier feature's
  decision.

## 2. Rule

A plan pass may create a file under `specs/` and edit one. It may not delete, rename or move one,
because `specs/` is the decision record. It commits no other file. Ralph does not detect
uncommitted edits outside `specs/`.

At the end of a pass that changed a spec, the planner commits those changes in the repository that
owns them. A plan commit changes paths under `specs/` and nothing else. `specs/` means that
directory at any depth: `specs/features/03-foo.md` is under it.

The one exception is a gitlink. When the owning repository is a submodule of the workspace, the
workspace commit that bumps the submodule's pointer changes that path and is legal.

## 3. Behaviour

### Plan prompt

`prompts/plan.md` gets a commit step at the end of each pass. It states:

- Stage each changed spec by name with `git -C <toplevel> add -- <path>`. Stage nothing outside
  `specs/`. Never stage `IMPLEMENTATION_PLAN.md`, `PROGRESS.md`, a `PROMPT_*.md` file or `.ralph/`.
  Never run `git add -A` or `git add .`.
- Before committing, run `git -C <toplevel> diff --cached --name-only`. Every line must start with
  `specs/`. Unstage any line that does not.
- Commit each spec change with a Conventional Commits message of type `docs` and scope `specs`,
  for example `docs(specs): default X to Y when Z`. One commit per decision recorded in an
  existing spec; one commit per new spec. The submodule pointer bump keeps build's `chore: bump`
  subject.
- For the owning repository, the detached `HEAD` rule, the submodule pointer bump and pushing a
  nested repository, follow the same rules as build's "Where to commit".

Two existing lines change to match:

- The constraint "Plan only. Do NOT implement anything." becomes "Plan only. Commit spec changes and
  nothing else."
- The "Unresolved decisions" rule to record a decision in the relevant spec gains "then commit it".

### Clean `specs/` before plan

`plan` refuses to start when any repository in `repo_state` has an uncommitted change under its
`specs/`, whether staged, unstaged or untracked. Otherwise the planner cannot tell an operator's
edit from its own, and commits the operator's edit under its own message.

The check is a hard stop in `cmd_loop`'s plan branch, directly after `require_fresh_cycle` and
before `resolve_backend`, so neither `-n` nor `--dry-run` bypasses it. It leaves every file
unchanged, prints to stderr and exits 1:

```
Error: specs/ has uncommitted changes in <repo>.
Commit or stash them before running 'ralph plan'; plan commits its own spec changes.
```

`<repo>` is the first repository that fails, as `repo_state` lists it. The check is one shared
predicate, `have_dirty_specs`, so `auto` can use it too.

### Guard after each plan pass

Ralph takes `repo_state` before and after each plan pass. For every repository whose `HEAD` moved,
it lists the paths of each new commit with `git log --format= --name-only --no-renames`. A
repository that was `-` before the pass, or absent from the listing, counts every commit reachable
from `HEAD`. `--no-renames` lists a rename as a deletion plus an addition, so a moved spec is caught.

The pass fails when any of these holds:

- A new commit changes a path outside `specs/`, other than a path that is itself a repository in
  the listing (§2's gitlink exception). Ralph joins `<repo>/<path>` and strips the leading `./`,
  as `cycle_changed_files` does, and passes the path when the result equals a `repo_state` entry.
- A new commit deletes a path under `specs/`, checked with `--diff-filter=D`.
- A repository's `specs/` still has uncommitted changes after the pass. `have_dirty_specs` detects
  this.

On failure Ralph prints to stderr and exits 1, without undoing any commit:

```
Error: plan pass <N> committed <path> in <repo>, which is outside specs/.
Error: plan pass <N> deleted <path> in <repo>; plan may not delete or move a spec.
Error: plan pass <N> left uncommitted changes under specs/ in <repo>.
```

The guard runs after the pass and before Ralph's push. The plan convergence check is unchanged: `plan_state_hash` reads the working tree, so a commit is not a
change.

### Push after plan

The push after each iteration runs in plan mode as well as build mode, with the same skips: no
`origin`, no commit, `--dry-run` and the skip-push flag. A plan pass that committed nothing pushes
an unchanged branch, which is harmless. As in build, Ralph pushes the workspace and the planner
pushes any nested repository it committed in.

### `auto`

The phase 3 guard in `cmd_auto` gets a second check beside the stale-base refusal: when
`have_dirty_specs` holds, auto refuses to start the plan child. The stale-base check runs first.
The fix is a commit, not a fresh lifecycle, so unlike the stale-base refusal it writes the state
file, so that `--resume` continues from phase 3 once the operator has committed. The file has the
same shape as a child failure, so resume needs no change: `phase=3`, `phase_name=plan`,
`child_exit=1` and `failed_at`. It prints to stderr and the report, then exits 1:

```
Error: specs/ has uncommitted changes in <repo>.
Commit or stash them, then run 'ralph auto --resume'.
```

The check runs at phase 3, not before phase 1. `archive` moves only the loop artifacts and `init`
creates `specs/` empty, which git does not see, so neither can dirty `specs/`. A resume at phase 4
or later never plans.

## 4. Documentation

- `CLAUDE.md` and `AGENTS.md`: the core loop flow's step 7 no longer says plan never commits. Step
  6 says the push runs after plan passes as well. The hard-precondition paragraph names the clean
  `specs/` check. The paragraph on `auto`'s phase guards names the second phase 3 check.
- `README.md` "Commit style": plan commits its spec changes as `docs(specs)` commits.
- `README.md` quick start and `auto` snippet: commit the spec before `ralph plan -g`.
- `docs/plan-format.md`: the precondition paragraph states the clean `specs/` rule.
- `--skip-push`: the help text in `ralph` and the `README.md` options row say it also covers plan.
- `docs/meta-repositories.md`: the note on where build runs its git commands also covers the plan
  prompt.
- Code comments: the five comments in `ralph` that say plan never commits are corrected. They sit
  at `mode_converges_on_plan`, `plan_state_hash`, the per-iteration snapshot, the push and the
  early exit.

## 5. Testing

### Clean `specs/` before plan

- `plan -g` fails with the error when `specs/` holds an unstaged edit, a staged edit, or an
  untracked file, and leaves the working tree unchanged.
- The same holds for a spec in a nested directory, `specs/features/x.md`.
- The same holds for a nested repository's `specs/` in a meta workspace.
- `plan --dry-run` and `plan -n 1` fail the same way.
- `plan` runs when `specs/` is clean and a file outside `specs/` is dirty.

### Guard after each plan pass

Each test uses a mock backend that makes the stated commits.

- A pass that commits an added spec and an edited spec, including one under `specs/features/`,
  passes, and the workspace is pushed.
- A pass that commits `README.md` fails with the outside-specs error and is not pushed.
- A pass that deletes or renames a spec fails with the deletion error.
- A pass that edits a spec and does not commit it fails with the uncommitted error.
- A pass that commits nothing passes.
- A pass that commits a spec in a nested repository and bumps its gitlink in the workspace passes.
- A pass in a repository with no commits before the pass is checked across every commit.

### `auto`

- `auto` with a dirty `specs/` runs phases 1 and 2, refuses at phase 3, starts no plan child, and
  writes the state file at phase 3.
- After the spec is committed, `auto --resume` starts the plan child.

## 6. Accepted risks

- **The planner can commit over its own mistakes.** The guard checks where a commit lands, not
  whether its content is right. A bad decision recorded in a spec is committed and pushed. Review
  reads the anchor set as the standard, so a wrong spec clause becomes the standard.
- **A new spec must be committed before planning.** The operator commits a spec before planning
  against it, because the precondition cannot tell an operator's draft from the planner's edit.
- **Uncommitted edits outside `specs/` go unseen.** The guard checks commits and `specs/`, so a
  planner that edits another file and leaves it uncommitted passes.
- **Several plan passes, several commits.** A decision revised in a later pass produces a second
  commit, not an amended one. The history stays honest, at the cost of noise.
- **A rejected commit stays on the branch, pushed or not.** Ralph stops without rewriting history,
  and the operator reverts it.

## 7. Out of scope

- Commits made by Ralph itself. The planner writes the message, because only it knows the
  decision.
- Splitting a spec into features. The operator does it outside Ralph, so plan never moves a spec.
- A convention for where a new spec goes, such as `specs/features/`. Plan writes the new spec
  where the goal points or at the top of `specs/`.
- Any change to build or review. Both still never edit `specs/`.
