# Nested Git Repositories

Ralph measures a build iteration by watching `HEAD`. `cmd_loop` snapshots `git rev-parse HEAD`
before the backend runs and compares it after, and three sites consume that one pair: the build
noop exit, `write_iteration_metrics`, and the push block.

That measurement assumes the workspace is one repository. A meta repo breaks the assumption. It
holds no service code of its own; a sync script clones each service into a gitignored `source/`
directory, and every clone is a normal, independent repository with its own remote and branch. The
build agent edits a file under `source/`, commits it in that nested repository, and the workspace
`HEAD` never moves.

Ralph then reads the iteration as having done nothing. Two such iterations in a row end the run
(`ralph:1569`), and a build that was shipping plan items stops at iteration 2 of 50.

**This spec delivers one outcome: a build loop runs to its full iteration count when the commits
land in nested repositories.** It changes the change verdict and the metrics `noop` flag, and
nothing else. The aggregate metrics that follow from the same listing — summed commits, files
changed and insertions/deletions — are deliberately not built here.

## 1. Model

**A build iteration changed something when any repository in the workspace moved.**

The workspace repository stops being special. Ralph takes a listing of every repository it can see
and each one's `HEAD`, before and after the iteration, and compares the two listings as strings.

This is the pattern `plan_state_hash` already uses for the non-committing modes: fingerprint the
thing the iteration is allowed to change, and compare the fingerprint. The difference is only what
gets fingerprinted.

## 2. Discovery

Ralph finds repositories by scanning the filesystem. It reads no manifest and takes no
configuration:

```sh
find . -maxdepth 6 -name .git -prune -print
```

A manifest was rejected because the format is one project's convention — this meta repo's
`repos.json` — and ralph is a generic tool. Configuration was rejected because a list of paths goes
stale the moment the sync script adds a repository, and the staleness is silent.

Four properties of that command matter:

- **No `-mindepth`.** The scan finds the workspace's own `./.git` at depth 1 and that is wanted: the
  workspace is one more entry in the listing, addressed through `git -C` like every other, so no
  branch in the code special-cases it. `-mindepth 2` would be wrong for a second reason — it
  suppresses evaluation of the whole expression below that depth, so `-name .git -prune` never fires
  at depth 1 and `find` descends into `./.git` hunting for matches at depths 2 to 6.
- **`-maxdepth 6`** bounds the walk. The bound applies to the `.git` entry, so a repository whose
  `.git` sits at depth 6 (`a/b/c/d/e/.git`) is watched and one at depth 7 is not. The meta repo
  needs depth 4 (`citc/<service>/source/.git`), so 6 leaves headroom. Measured on a hostile tree of
  60 repositories and 17 `node_modules` directories: 0.53 s cold and 0.02 s warm, against 2.25 s
  cold and 0.10 s warm unbounded. Iterations run for minutes, so either is affordable; the bound is
  taken for the cheaper walk rather than out of necessity.
- **`-prune`** stops the walk at each hit, so `find` never descends into a `.git` directory hunting
  for matches among the objects. It prunes the `.git` entry itself and not its parent, so **a
  repository nested inside a watched repository is also watched.** That is accepted: the outer
  repository does not record the inner one's commits, so watching both is the over-detection bias
  applied consistently.
- **`-name .git`** matches a `.git` file as well as a directory, so git worktrees and true
  submodules are found alongside plain clones. Section 3 treats all three identically.

The scan root is the working directory, not `git rev-parse --show-toplevel`. Ralph already resolves
`IMPLEMENTATION_PLAN.md`, `specs/` and `PROGRESS.md` relative to the working directory, and a scan
root that disagreed with those would be a second, invisible notion of where the workspace is.

**The scan runs before and after every iteration**, not once per run. A fresh meta repo clone has no
`source/` directories at all until the sync script runs, and an iteration may be the thing that runs
it. A set fixed at loop start would be empty for exactly that run, which is the bug this spec exists
to fix.

**Discovery does not consult `.gitignore`.** Being ignored is what makes the meta repo's clones
invisible to the workspace `HEAD`, but it is not the defining property: a nested repository that is
merely untracked has the same defect. Any `.git` is a repository.

## 3. The change verdict

The fingerprint is a sorted listing of one `<path> <sha>` line per repository:

```
. 84d5fc6b1a...
./citc/auto-adapter-service/source 9f1c2ad...
./mountain/hades/source -
```

`LC_ALL=C sort` fixes the order across platforms, matching `plan_state_hash`.

**The verdict is string inequality between the before and after listings.** Any difference is a
change: a moved `HEAD`, a repository that appeared, a repository that vanished.

The paths are left exactly as `find` emits them, with the `./` prefix the nested entries carry and
the bare `.` the workspace entry reduces to. Normalising them would be presentation work on a string
that is only ever compared to another string produced the same way, and this slice never splits a
line back into its parts.

### The reason a `HEAD` moved is never examined

The sync script does `fetch`, `checkout` and `merge --ff-only` on every repository. If an iteration
runs it, ten `HEAD`s can move without the agent writing a line of code, and ralph will call that a
change.

That is deliberate. The two errors are not symmetric. Over-detection delays the noop exit by one
iteration and the run still stops, bounded by `max_iterations`. Under-detection is the defect this
spec fixes: it truncates a run that was making progress. Every rule below resolves the same way.

Distinguishing agent commits from upstream ones was considered and rejected on both available
signals. Filtering by commit date fails when upstream pushes during the iteration. Excluding
commits reachable from a remote-tracking ref fails when the agent commits and pushes, which is what
the build prompt tells it to do.

### Repositories with no readable `HEAD`

A freshly `git init`ed or empty-cloned directory has a `.git` and no commit, so its `HEAD` does not
resolve. That entry records the sentinel `-`.

**`git rev-parse -q --verify HEAD` is required, and plain `git rev-parse HEAD` is forbidden.** In a
commitless repository, plain `rev-parse` prints the literal string `HEAD` on *stdout* and then exits
128, so a `|| echo -` fallback appends to that output rather than replacing it: the entry becomes
`<path> HEAD` and a stray `-` line with no path at all joins the listing. `rev-parse -q --verify`
prints nothing and exits 1, so the fallback works as written.

The fallback is `echo -`, and it holds because ralph is bash. The same line under zsh emits an empty
string, since zsh reads the lone `-` as an option terminator, so the entry would lose its sentinel
and the listing would carry a trailing space instead. Verified on git 2.47.3.

The sentinel keeps such a repository in the listing, so its first commit flips `-` to a sha and
reads as a change. A transient git failure also flips the entry and also reads as a change, which is
the over-detection bias applied consistently.

### Uncommitted changes are not a change

A nested repository with a dirty worktree has not moved its `HEAD`, so it does not count. This is
the rule the workspace repository already follows — an iteration that edits files and commits
nothing is a noop today — and applying one rule at both levels keeps the semantics explainable.

The alternative fails on its own terms: a stray edit the agent abandons would read as a change on
every subsequent iteration, the noop exit would never fire, and every run would reach its cap.

## 4. The metrics `noop` flag

`write_iteration_metrics` computes `noop` from the two `HEAD`s it is passed, then lets the caller
override it: `plan_noop` already replaces that verdict for the non-committing modes, because
`HEAD` cannot describe an iteration that never commits. **Build mode now uses the same override**,
carrying the section 3 verdict.

The thirteenth parameter is renamed from `plan_noop` to `noop_override` and is populated in every
mode. The caller computes it in the branch that already exists: `mode_converges_on_plan` compares
the two `plan_state_hash` values as it does today, and the else branch compares the two listings.
No parameter is added and no call site gains an argument.

**Nothing else in the record changes.** `commits`, `files_changed`, `insertions` and `deletions`
stay derived from the workspace `HEAD` pair and stay 0 for a nested-only iteration, so that record
reads `noop: false, commits: 0, +0/-0`. The inconsistency is real and is the price of this slice:
the loop verdict and the `noop iterations` total in `ralph metrics` now agree, and the sums stay
understated until they are specified in their own right.

A single-repository run is unaffected in every field. With no nested repository present the listing
holds one entry, so the override always equals the `HEAD` comparison it replaces.

## 5. Script changes

The listing is built by one function and consumed at the sites that hold a `HEAD` today:

```sh
repo_state() {
    local repo
    while IFS= read -r gitpath; do
        repo=${gitpath%/.git}
        printf '%s %s\n' "$repo" \
            "$(git -C "$repo" rev-parse -q --verify HEAD 2>/dev/null || echo -)"
    done < <(find . -maxdepth 6 -name .git -prune -print 2>/dev/null) | LC_ALL=C sort
}
```

- **`ralph:1149`** — `state_before=$(repo_state)` is taken beside the existing
  `head_before=$(git rev-parse HEAD)`, which stays because section 4 leaves the metrics sums on it.
  `state_before` and `state_after` are declared together on that `local` line, so `set -u` is
  satisfied on the dry-run path where the second is never assigned.
- **`ralph:1484`** — one unconditional `state_after=$(repo_state)` is taken after the pass and
  *before* the `if $metrics_enabled` block that opens at `ralph:1487`. Metrics may be disabled
  (`ralph:1009` turns them off for `--no-metrics` and for a dry run); change detection may not. A
  listing declared inside that block would leave `--no-metrics` builds either dying on an unbound
  variable under `set -u`, or comparing against an empty string that never matches, so the noop exit
  would never fire for that whole class of runs.
- **`ralph:1475`** — `plan_noop` becomes `noop_override` and gains the else branch of section 4.
- **`write_iteration_metrics`** — the thirteenth parameter is renamed to match. Its body is
  otherwise untouched.
- **`ralph:1566`** — the build noop exit compares `state_before` with `state_after` instead of
  calling `git rev-parse` a second time. The 2-consecutive-noop threshold is unchanged, and `-n`
  still disables the exit entirely.

**One code path, no mode branch.** `repo_state` runs in every mode, including plan and review, even
though those converge on `plan_state_hash` and never commit. Gating the scan on mode would add a
fourth site that tests the mode, and `mode_converges_on_plan` exists in this script precisely
because that pattern was already a hazard at three. The cost is one sub-second scan per pass in a
mode that will not use the result.

Plan and review behaviour is otherwise untouched: they fingerprint `IMPLEMENTATION_PLAN.md` plus
`specs/`, neither commits, and nested repositories change nothing for them.

## 6. Documentation

One existing statement becomes wrong and must change with the code. This is a correctness fix to a
measurement ralph already documents, not a feature, so it earns no new section anywhere.

- **CLAUDE.md and AGENTS.md** — the loop-flow step that reads "Build mode watches `HEAD` and stops
  after 2 consecutive noops, unless `-n` was passed" becomes: build mode watches every git
  repository beneath the workspace, not just the workspace's own `HEAD`, and stops after 2
  consecutive iterations in which none of them moved.
- **README.md** — the `### Loop metrics` paragraph lists "git activity (commits, files changed,
  insertions/deletions) ... and a noop flag". One clause states that the noop flag covers every
  nested repository while the counts remain workspace-only.

## 7. What this does not fix

Ralph pushes nothing nested. The push block (`ralph:1532`) keeps pushing the workspace repository
and only that. A commit the agent makes inside a nested repository and does not push stays local,
and ralph neither pushes it nor warns about it.

`prompts/build.md` is unchanged, so where to commit remains the agent's judgement. This is a known
gap and worth stating plainly, because the bundled `/commit` skill uses bare `git status`,
`git diff` and `git add`: run from the workspace root, those see nothing at all inside a gitignored
nested repository, so the agent must already be inside that repository for the skill to work.

Nothing announces what is being watched. A scan that finds no repository is indistinguishable from
today's behaviour, which is what keeps every existing output assertion in the test suite honest, and
a misconfigured tree presents as the original bug with no extra diagnosis.

The git counts in `metrics.jsonl` stay workspace-only, per section 4.

## 8. Testing

All change-detection tests use a mock backend. `--dry-run` cannot exercise them: `ralph:1558` wraps
the whole early-exit block in `if ! $dry_run`, so a dry-run test would assert nothing. Nested
repositories are created with `git init` in a subdirectory of the test workspace; no real clone or
remote is required.

- A commit made in a gitignored nested repository counts as a change: the build loop does not exit
  after two such iterations.
- Two iterations that move no repository at all still exit early, unchanged.
- A nested repository that appears during an iteration counts as a change.
- A nested repository that vanishes during an iteration counts as a change.
- Uncommitted changes in a nested repository do not count as a change, while a commit in that same
  repository on the next iteration does. Both halves in one test, so neither half can pass against
  a script that watches nothing.
- A commitless nested repository is stable across iterations: an otherwise idle run with one present
  still exits after two noops, and that repository's first commit counts as a change. The sentinel
  value itself is not asserted — it never leaves the script, so it is not observable from ralph's
  output, and section 3's `rev-parse -q --verify` requirement stands as a code rule with no test
  behind it.
- An unchanged nested repository alongside a moved one does not, on its own, prevent the noop exit.
- A nested repository whose path contains a space is detected, proving the listing is never split on
  whitespace.
- A repository whose `.git` is a file (worktree form) is watched.
- A repository whose `.git` is at depth exactly 6 **is** watched and one at depth 7 is not. Both
  bounds are asserted in the same test, so neither can pass against a script that watches nothing.
- A repository nested inside a watched repository is watched, and so is the outer one.
- `ralph build -n N` still ignores the noop exit; the verdict change does not resurrect it.
- `ralph build --no-metrics` still detects a nested change and still exits after two noops, proving
  the listing is not scoped to the metrics block.
- Metrics record `noop: false` for an iteration that only committed in a nested repository, with
  `commits` still 0.
- Plan and review still converge on `plan_state_hash`, with a moved nested repository proving it
  does not affect them.
- Existing build, plan, review and metrics tests continue to pass.

## 9. Out of scope

- Aggregate git counts in `metrics.jsonl` — `commits`, `files_changed`, `insertions` and
  `deletions` summed across repositories, with the join, sentinel and ancestry rules that
  requires.
- Any announcement of the watched set, and any change to loop output.
- Pushing nested repositories, and any per-repository push, upstream or branch handling.
- Warning about nested commits that were never pushed.
- Changes to `prompts/build.md`, `prompts/plan.md`, `prompts/review.md` or the `/commit` skill.
- Per-repository detail in `metrics.jsonl`, and any new column in `ralph metrics`.
- A flag or configuration file to enable, disable or scope the scan.
- Reading `repos.json`, running the sync script, or any awareness of how nested repositories arrived.
- Treating uncommitted work, stashes or untracked files as progress.
- Nested repositories in plan or review mode, which commit nothing.
