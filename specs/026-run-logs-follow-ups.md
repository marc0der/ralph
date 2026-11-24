---
id: "026"
created: 2026-11-24
area: [auto, output]
amends: ["023"]
---

# Run Logs Follow-ups

The review of the spec 023 cycle left three questions that spec 023 does not settle. A resume
without a run directory forgets the recorded run. `auto` passes an operator's `RALPH_RUN_DIR` on
to its children. And the rollup table depends on the platform's `column`, which aligns it
differently under BSD, and only a test shim checks the BSD case. This spec settles all three. It
also adds a macOS CI job, so that BSD tools run the suite.

This spec amends `023-run-logs-and-metrics.md` §3 `cmd_auto`, where `write_auto_state` adds a
`run=` line and `auto` exports no `RALPH_RUN_DIR` when it has no run directory. It amends §3
`ralph metrics [path]`, where the rollup and per-iteration tables are aligned. It amends §5,
where the tests are listed.

## 1. Problem

- **A resume forgets its run.** `write_auto_state` writes `run=${RALPH_RUN_DIR:-}`. Under
  `auto --resume --no-metrics`, or after `auto` fails to create the run folder, the variable is
  empty, so `.ralph/auto-state` gets `run=` with no value. A later `auto --resume` prints
  `Resumed into a new run directory; earlier phases are not in it.` and creates a second run
  directory, although the recorded one still exists.
- **An exported `RALPH_RUN_DIR` leaks into the lifecycle.** `cmd_loop` removes the variable from
  its environment, and `cmd_auto` does not. With `RALPH_RUN_DIR=/some/dir` exported and
  `--no-metrics` passed, every child phase writes its phase folder into `/some/dir`, and
  `write_auto_state` records `run=/some/dir`. Spec 023 says `auto` "exports no `RALPH_RUN_DIR`"
  in this case.
- **The table depends on `column`.** `print_tsv_table` pipes rows to `column -t -s $'\t'`, and
  falls back to `cat` when `column` is absent. BSD `column` merges adjacent tabs, so an empty cell
  shifts every later cell one column left. `print_run_rollup` works around this with a
  one-space cell. Without `column`, the table is not aligned at all. CI runs on `ubuntu-latest`
  only, so the BSD case is checked only through a `column` shim that prints its input unchanged.

## 2. Rule

- **A resume keeps its recorded run.** On `auto --resume`, when `auto` holds no run directory of
  its own, `.ralph/auto-state` keeps the `run=` value it recorded.
- **`auto` clears `RALPH_RUN_DIR`.** `cmd_auto` removes the variable from its environment before
  it does anything else. Only a run directory that `auto` itself creates or reuses reaches a child.
- **Ralph aligns its own tables.** Ralph pads table cells in its own code and never calls
  `column`. The output is the same on every platform.
- **CI runs the suite on macOS.** A second BATS job runs on `macos-latest`.

## 3. Behaviour

### `cmd_auto`

- The first statement of `cmd_auto` unsets `RALPH_RUN_DIR`. This applies to every form of `auto`,
  `--dry-run` and `--resume` included.
- `write_auto_state` writes the run directory that `auto` holds, as today. When `auto` holds none
  and runs with `--resume`, it writes the `run=` value read from `.ralph/auto-state` at the
  start, unchanged, even when that directory no longer exists. A run without `--resume` that holds
  no run directory writes `run=` with no value, as today.
- `auto` holds no run directory under `--no-metrics`, and after it fails to create the folder.
  The `Resumed into a new run directory` notice and the `lifecycle metrics disabled` warning are
  unchanged.
- `write_auto_state` takes the run value as an argument. It does not read `RALPH_RUN_DIR` or a
  variable local to `cmd_auto`.

### Table alignment

- `print_tsv_table` reads tab-separated rows from stdin. It sets the width of each column to its
  widest cell, pads each cell with spaces to that width, and joins the cells of a row with two
  spaces. It does not pad the last cell of a row, and it writes no trailing space. This matches
  today's GNU `column -t -s $'\t'` output, so the existing table assertions still hold.
- An empty cell keeps its column. It is padded like any other cell.
- Width counts characters, not bytes, under a UTF-8 locale. A rollup `state` such as
  `skipped — no cycle base` holds a multibyte dash, so a byte count misaligns its row.
  Implementations of `awk` differ here: GNU `awk` counts characters, `mawk` and older BSD `awk`
  count bytes. The plan chooses a method that counts characters on GNU and BSD systems alike.
- `print_tsv_table` has no `column` branch and no `cat` fallback.
- `print_run_rollup` writes an empty cell in place of the one-space cell for a phase without a
  folder. The comment about BSD `column` goes with it.

### CI

- `.github/workflows/ci.yml` gains a job `test-macos`, named `BATS Tests (macOS)`, on
  `macos-latest`. It installs `bash`, `bats-core`, `jq` and `yq` with Homebrew, puts Homebrew's
  `bash` first on `PATH`, prints `bash --version` and `yq --version`, and runs `bats test/`.
- The job also installs `gnu-getopt` with Homebrew and puts its `bin` directory on `PATH` ahead of
  `/usr/bin`. `cmd_loop` and `cmd_auto` parse their flags with util-linux `getopt` and its
  `--long` option, which the macOS `getopt` lacks. Homebrew installs `gnu-getopt` keg-only, so
  its `bin` directory is not on `PATH` by default. Planner decision, 2026-11-24: without it, no
  loop or `auto` test can pass on macOS, this spec's §5 tests included. It assumes that the
  `macos-latest` image puts no util-linux `getopt` on `PATH`.
- The `shellcheck` and `test` jobs are unchanged.

## 4. Documentation

- `CLAUDE.md` and `AGENTS.md`: the CI sentence says that BATS runs on Linux and macOS.

## 5. Testing

- `test/auto.bats`:
  - `auto --resume --no-metrics` over an `auto-state` whose `run=` names an existing run folder
    keeps that `run=` value after the resumed phase fails. A following `auto --resume` reuses the
    folder and prints no `Resumed into a new run directory` notice.
  - With `RALPH_RUN_DIR` exported to an existing directory, `auto --no-metrics` writes nothing into
    that directory, and its `auto-state` holds `run=` with no value.
  - With `RALPH_RUN_DIR` exported to an existing directory, `auto` with metrics creates its own run
    directory under `.ralph/logs/` and writes nothing into the exported one.
- `test/metrics.bats`:
  - The test `a rollup row for a phase without a folder fills every cell for BSD column` is
    replaced. The new test puts a `column` shim that exits 1 first on `PATH` and asserts that the
    rollup output is unchanged, so Ralph never calls `column`.
  - A rollup with a phase without a folder, whose `state` holds `—`, prints its `EXIT` cell at the
    same character offset as the `EXIT` header, under `LC_ALL=C.UTF-8` or another UTF-8 locale.
  - A table with an empty cell in a middle column keeps every later cell in its column.
  - No line of a rollup or per-iteration table ends in a space.
- The macOS job runs the whole suite, including these tests, on BSD tools.

## 6. Accepted risks

- **The build cannot see the macOS job.** The build loop runs on Linux, and CI runs only when the
  branch is pushed for a pull request. A failure that only BSD tools expose shows up on the pull
  request, after the cycle ends. The operator handles it with a fix item in a later cycle.
- **The first macOS run may be red.** No test has run on BSD tools until now, and spec 009 already
  records one BSD difference in `mktemp`. Failures outside this spec's tests are not part of this
  spec. The operator decides whether to fix them or mark the job non-blocking until they are fixed.
- **The macOS job uses Homebrew `bash`, not `/bin/bash` 3.2.** `ralph` already uses `mapfile`,
  which needs bash 4, so it cannot run under `/bin/bash` 3.2 today. The job checks BSD tools, not
  bash 3.2.
- **The macOS job uses Homebrew `gnu-getopt`, not the macOS `getopt`.** `ralph` needs the
  `--long` option of util-linux `getopt` today, as it needs bash 4. The job does not check the
  macOS `getopt`.
- **A resume without metrics leaves gaps in the recorded run.** Under `--no-metrics`, the phases
  that run write no phase folder and no `auto.json` entry. A later resume with metrics keeps the
  earlier entries, so the run shows those phases with their old state.
- **A recorded run that no longer exists is carried forward.** The next resume with metrics finds
  it missing, creates a new run directory and prints the notice, as spec 023 requires.

## 7. Out of scope

- Support for `/bin/bash` 3.2 on macOS, and the removal of `mapfile`.
- Support for the macOS `getopt`.
- A macOS ShellCheck job.
- Running the suite on macOS from inside the build loop.
