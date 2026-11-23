---
id: "023"
created: 2026-11-23
area: [output, auto, git]
amends: ["009", "012"]
related: ["011", "019", "021"]
---

# Run Logs and Metrics

Each loop run writes its backend streams and its `metrics.jsonl` to
`.ralph/metrics/<branch>-<timestamp>-<pid>/`. This spec changes three things. It renames the
store to `.ralph/logs/`, because the streams are the record and the metrics are derived from
them. It groups every phase of one `auto` lifecycle under one run directory, and `ralph metrics`
summarises the lifecycle as a whole. It also counts git activity in every repository beneath the
workspace, not only the workspace.

This spec replaces `012-auto-lifecycle.md` §10, which left run-level grouping for later. It
amends `009-verbose-live-streaming.md` wherever that spec names the `.ralph/metrics/` path of
the retained stream file.

## 1. Problem

- **The lifecycle is scattered.** `ralph auto` runs up to five loop phases. Each one creates its
  own run directory, so the cost of one goal is the sum of five directories that the operator
  has to find by hand. `ralph metrics` with no argument reads only the newest directory, which
  after `auto` is retro's single pass.
- **Nested commits count as zero.** `write_iteration_metrics` runs `git rev-list` and
  `git diff --shortstat` on the workspace `HEAD` only. A build that made 14 commits in
  `sdkman-broker-2` recorded `commits: 0` on every iteration. The noop flag is already correct,
  because the caller passes its verdict from `repo_state`.
- **The name is wrong.** `.ralph/metrics/` mostly holds backend streams, which are logs. The
  metrics are one file derived from them.

## 2. Rule

- **Store.** Ralph writes every run under `.ralph/logs/`. The first command that writes or reads
  runs moves an existing `.ralph/metrics/` there.
- **Layout.** A run directory holds one subdirectory per phase it ran. A standalone phase command
  is a run with one phase. An `auto` lifecycle is one run, with up to five phase subdirectories
  and an `auto.json`.
- **Resume.** `auto --resume` continues the run it interrupted. A phase that runs again appends to
  its own subdirectory.
- **Counting.** The `git` counts of an iteration are sums over every repository whose `HEAD`
  moved during the pass, and a `git.repos` array breaks them down.
- **Summary.** `ralph metrics` on an `auto` run prints one row per phase and a lifecycle total.
  On a single phase it prints today's per-iteration table.

## 3. Behaviour

### Layout

```
.ralph/logs/<branch>-<YYYYMMDD-HHMMSS>-<pid>/
  auto.json                  # auto runs only
  plan/metrics.jsonl
  plan/iter-001.stream.jsonl
  build/metrics.jsonl
  build/iter-001.stream.jsonl
  review/...
  fix/...
  retro/...
```

- The run directory name keeps today's form: the branch with `/` replaced by `-`, the start time,
  and the PID of the process that created it. For `auto` that is the `auto` process.
- The phase subdirectory is named after the config section (`plan`, `build`, `fix`, `review`,
  `retro`), so `fix` and `build` never share one, although both run build mode.
- `metrics.jsonl` records and stream file names keep their current format.

### `cmd_loop`

- When `RALPH_RUN_DIR` is set and names a directory, the run writes to
  `$RALPH_RUN_DIR/<section>/`. Otherwise it creates a new run directory as today and writes to
  `<run>/<section>/`.
- When `<section>/metrics.jsonl` already holds records, the run continues their numbering: its
  first iteration takes the highest recorded `iteration` plus one, in the record and in the
  stream file name. The banner's `ITERATION n / max` keeps counting from 1, because it counts
  this run's passes against this run's cap.
- `--no-metrics`, `metrics: false` and `--dry-run` disable the store as today. The flag and key
  names do not change.
- The `Metrics:` banner line and the `Metrics recorded:` closing line name the phase
  subdirectory's `metrics.jsonl`.

### `cmd_auto`

- Unless metrics are disabled, `auto` creates the run directory before phase 1 and exports
  `RALPH_RUN_DIR` to every child. `archive` and `init` write nothing there.
- `auto` writes `auto.json` before phase 1 and rewrites it after each phase:

  ```json
  {"goal": "…", "branch": "…", "started": "<ISO 8601 UTC>",
   "phases": [{"phase": 3, "name": "plan", "state": "ran", "exit": 0,
               "started": "…", "ended": "…"}]}
  ```

  `state` is the same text the closing `auto_report` prints for that phase, for example `ran` or
  `skipped — no open items`. A phase that runs again on resume replaces its entry. The rewrite goes
  through a temp file in the run directory and `mv`, so a reader never sees half a file.
- `write_auto_state` adds a `run=<run directory>` line.
- `--resume` reads `run=`. When that directory exists, `auto` reuses it and exports it again.
  When the line is missing or the directory is gone, `auto` creates a new run directory and
  prints `Resumed into a new run directory; earlier phases are not in it.`
- `--no-metrics` creates no run directory and no `auto.json`, as today.

### Git counts

`cmd_loop` records `repo_state` before and after every pass in every mode, and passes both
listings to `write_iteration_metrics` in place of the two workspace heads. For each repository in
the after-listing whose SHA is not `-` and differs from its before-line:

| Before | Commits | Diff base |
|--------|---------|-----------|
| a SHA | `git -C <repo> rev-list --count <before>..<after>` | `<before>` |
| `-`, or absent | `git -C <repo> rev-list --count <after>` | the empty tree |

The diff is `git -C <repo> diff --shortstat <base> <after>`. The empty tree's SHA comes from
`git hash-object -t tree /dev/null`, so the SHA-256 object format works too.

The record keeps its `git` keys and adds one:

```json
"git": {"commits": 15, "files_changed": 9, "insertions": 410, "deletions": 56, "noop": false,
        "repos": [{"repo": ".", "commits": 1, "files_changed": 2, "insertions": 30, "deletions": 4},
                  {"repo": "./sdkman-broker-2", "commits": 14, "files_changed": 7,
                   "insertions": 380, "deletions": 52}]}
```

- The scalar keys are the sums over `repos`.
- `repos` lists only the repositories that moved, sorted as `repo_state` sorts them, and is `[]`
  for a pass that moved none.
- A repository that vanished, or whose `HEAD` became `-`, is left out.
- `noop` keeps its current source: the caller's verdict.

### `ralph metrics [path]`

The argument may be a run directory, a phase subdirectory, or a `metrics.jsonl` file.

- **No argument.** Ralph picks the run under `.ralph/logs/` that holds the most recently modified
  `metrics.jsonl`, and treats it as a run-directory argument.
- **A run directory with `auto.json`.** Ralph prints the rollup. Its header gives the run path
  with `(auto)` and the goal. The table has one row per phase subdirectory, in lifecycle order,
  with these columns: `PHASE`, `MODEL/EFFORT`, `ITERS`, `WALL`, `COST`, `OUT_TOK`, `COMMITS` and
  `EXIT`. `MODEL/EFFORT` comes from the phase's first record and prints `default` for a null
  effort. `EXIT` comes from `auto.json`. The table is followed by a `Totals:` line over every
  record of every phase.
- **A run directory without `auto.json`.** This is a standalone run. When it holds one phase
  subdirectory, Ralph prints that phase's per-iteration table. When it holds more than one, Ralph
  prints the rollup with `-` in `EXIT`.
- **A phase subdirectory or a `metrics.jsonl` file.** Ralph prints today's per-iteration table and
  `Totals:` line for that phase.
- **The `Repos:` line.** After `Totals:`, Ralph prints `Repos:` with one
  `<repo> <commits> (+<ins>/-<del>)` group per repository, summed over the records it read, when
  those records name more than one repository. Records without `repos` contribute nothing to the
  line.
- **Old runs.** A run directory that holds `metrics.jsonl` at its top level, and no phase
  subdirectory, is an old run. Ralph prints its per-iteration table.
- `metrics_summary_suffix`, the one-line summary printed after each pass, reads the new scalar
  sums. Its format does not change.

### Moving `.ralph/metrics/`

`migrate_run_store` runs first in `cmd_loop` (before `arm_retro_pass`), in `cmd_auto`, and in
`cmd_metrics`:

- When `.ralph/metrics/` does not exist, it does nothing.
- When `.ralph/logs/` does not exist, it renames `.ralph/metrics/` to `.ralph/logs/` and prints
  `Moved .ralph/metrics/ to .ralph/logs/.` to stderr.
- When both exist, it moves each entry of `.ralph/metrics/` into `.ralph/logs/` unless an entry of
  that name is already there. It removes `.ralph/metrics/` only when it is empty afterwards. For
  each entry it leaves behind, it prints
  `Warning: kept .ralph/metrics/<name>; .ralph/logs/<name> already exists.`
- A failed move only warns. It never stops the command.

### Other readers of the path

- `retro_artifact_state` prunes `$ARCHIVE_DIR/logs`, and `$ARCHIVE_DIR/metrics` while that
  directory still exists, so a retro pass inside `auto` may write its own stream files.
- `prompts/plan.md` and `prompts/retro.md` name `{{WORKSPACE}}/.ralph/logs/` where they name
  `.ralph/metrics/` today.
- The `--no-metrics` help text names `.ralph/logs/`.

## 4. Documentation

- `README.md`: the metrics paragraph, the `metrics` command row, the `--no-metrics` row and the
  `.ralph/` row name `.ralph/logs/`. The metrics paragraph says that `auto` keeps one run for the
  lifecycle and that `ralph metrics` shows it phase by phase.
- `docs/meta-repositories.md`: the line "Metrics count git activity in the workspace only" is
  replaced by one that says counts cover every repository, with a per-repository breakdown.
- `CLAUDE.md`: the core loop flow names `iter-NNN.stream.jsonl` under `.ralph/logs/<run>/<phase>/`,
  and the `metrics` row says it summarises a run, phase by phase for `auto`.

## 5. Testing

`test/metrics.bats` unless stated otherwise.

- **Layout.** A standalone `build` writes `<run>/build/metrics.jsonl` and
  `<run>/build/iter-001.stream.jsonl` under `.ralph/logs/`. `fix` writes under `fix/`.
- **`RALPH_RUN_DIR`.** With the variable set, a loop writes into `$RALPH_RUN_DIR/<section>/` and
  creates no other run directory.
- **Appending.** A second run into the same phase subdirectory numbers its first record and stream
  file one past the highest existing `iteration`.
- **Nested counts.** A mock backend that commits twice in a nested repository and once in the
  workspace yields `commits: 3` and a two-entry `repos` array with the right per-repository counts.
- **New repository.** A repository created and committed in during the pass counts its commits
  against the empty tree.
- **No movement.** A pass that moves no repository records `repos: []` and zero scalars.
- **Rollup.** A fixture run with `auto.json` and three phase subdirectories prints one row per
  phase in lifecycle order, the right `EXIT` values, a `Totals:` line over all records, and a
  `Repos:` line.
- **Old records.** A record without `repos` still summarises, and adds nothing to `Repos:`.
- **Old run.** A run directory with a top-level `metrics.jsonl` prints the per-iteration table.
- **Default pick.** With two runs, no argument picks the one with the newer `metrics.jsonl`.
- **Migration.** `.ralph/metrics/` alone is renamed. When both stores exist, a clashing entry stays
  behind with the warning and the others move.
- `test/auto.bats`: an `auto` run creates one run directory with phase subdirectories and an
  `auto.json` listing every phase. `auto-state` gains `run=`. `--resume` reuses that directory, and
  the re-run phase appends to its subdirectory. `--resume` with the directory gone creates a new
  one and prints the notice. `--no-metrics` creates no run directory.
- `test/retro.bats`: a retro pass whose stream files land under `.ralph/logs/` passes
  `check_retro_pass`.
- The existing tests that name `.ralph/metrics/` name `.ralph/logs/<run>/<section>/` instead.

## 6. Accepted risks

- **A cloned repository inflates the counts.** A pass that clones a repository counts its whole
  history as commits of that pass. Builds rarely clone, and the per-repository breakdown shows
  where the number came from.
- **`rev-list a..b` after a branch switch.** When the agent checks out another branch, the count is
  the commits reachable from the new `HEAD` and not from the old one. That is still the work that
  is now on `HEAD`.
- **A resumed phase mixes attempts.** Appending folds a failed attempt's iterations into the same
  phase row. The record of every attempt remains in `metrics.jsonl`, and the iteration numbers do
  not restart, so the attempts can still be told apart.
- **Concurrent `auto` runs in one workspace** share nothing but `.ralph/logs/`. Their directory
  names differ by PID, as today.

## 7. Out of scope

- Renaming the `--no-metrics` and `--metrics` flags or the `metrics` config key.
- Pruning or rotating old runs.
- Cost and token fields for backends other than `claude`.
