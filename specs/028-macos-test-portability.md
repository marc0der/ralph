---
id: "028"
created: 2026-11-24
area: [output]
related: ["027"]
---

# macOS Test Portability

Spec 027 added the `BATS Tests (macOS)` CI job and accepted that its first run might be red. It
is red: the same 25 tests fail on `macos-latest` on every run since the job was added, while the
Linux job is green. Every first failure lies in the test suite. Some of the 25 tests never ran
past their setup on macOS. The tests and their mock backends call GNU-only command forms, and some
assertions depend on the length of the temporary directory or on the wording of glibc's `getopt`
error. This spec makes the suite pass on both platforms without changing what `ralph` does. It
also names the Linux job for its platform, as the macOS job already is.

## 1. Problem

The failures fall into five causes.

- **The shared committing mock cannot tick an item.** The mock in `test/test_helper.bash` ticks
  the first `- [ ]` line of the file with a GNU-only `sed` edit that changes only the first
  match, using in-place editing with no backup suffix. BSD `sed` rejects it, so no item is ticked.
  Build never ships, the review guard skips phase 5, and every later phase reports a different
  state. Failing:
  - `auto.bats`: `a lifecycle where every phase ran exits 0`, `a lifecycle whose review files
    nothing skips phase 6 and exits 0`, `a lifecycle whose fix skips still runs phase 7 after it`,
    `each phase that runs prints one run card title`, `a lifecycle with metrics leaves one run
    folder holding every loop phase`, `a lifecycle writes auto.json listing the seven phases in
    order`, `auto.json records the failed phase and the unreached ones after an abort`,
    `auto.json records the reason a phase was skipped`, `auto.json records the exit and times of
    each phase that ran, and null for one that did not`, `auto.json records the exit and end time
    of a phase that failed`.
  - `cards.bats`: `headline names the second item once the agent ticks the first`, `headline says
    no open item when the plan holds none at the iteration start`.
- **Other in-place edits have no backup suffix.** `auto.bats:218`, `cards.bats:759` and the
  mock in `review.bats:332` edit a file in place with no suffix. BSD `sed` reads the script as
  the suffix and fails with `invalid command code`. `review.bats:332` also edits only the first
  match with the GNU-only form. Failing:
  - `auto.bats`: `phase 6 is skipped with 'no plan artifacts' when PROGRESS.md vanishes mid-run`.
  - `cards.bats`: `footer keeps a tool list that fits the width`, `footer drops a tool list that
    passes the width`.
  - `review.bats`: `review fails when a pass un-ticks a shipped item`.
- **`paste` reads stdin with no file operand.** `metrics.bats:197`, `:227` and `:241` join lines
  with `paste` and no file operand. BSD `paste` needs `-` and prints its usage. Failing:
  - `metrics.bats`: `a second run into one phase folder continues the record and stream numbers`,
    `a record above the stream numbers wins, and leading zeros stay decimal`, `the highest record,
    not the last, numbers the next record in a folder without stream files`.
- **Card assertions depend on the temporary path length.** A macOS temporary directory sits under
  `/var/folders/…/T/`, which is much longer than `/tmp`. The central config path then makes the
  `config:` card row wider than the card, and the card shortens it, as it should. The central
  config file sits under the temporary directory, so its path, and the row, grow with that
  directory. The failure reproduces on Linux with a
  long `TMPDIR`. The `prompt:` row holds a path under the same directory, so two more tests that
  pass on macOS today fail under a longer one. Failing:
  - `cards.bats`: `run card names the local and central config sources with their section`.
  - `config.bats`: `the run card names the local and central sources`, `the shipped config.yaml
    validates and sets no backend-tied key`, `the shipped config.yaml drifts from no built-in in
    plan, build, fix, review and retro`.

  At risk:
  - `cards.bats`: `run card prints the branch and prompt rows`.
  - `config.bats`: `fix --dry-run runs build mode under the fix section`.
- **Assertions match glibc's `getopt` wording.** `auto.bats:90` and `pipeline.bats:168` expect
  `invalid option -- 'v'`. Homebrew's `gnu-getopt` gets its message from the macOS C library,
  which does not put quotes around the option letter. Failing:
  - `auto.bats`: `auto -v exits 1 with the getopt message`.
  - `pipeline.bats`: `build rejects -v`.

One more GNU-only form fails nothing today: the committing mock writes `date +%s%N` to make each
build's output line unique, and BSD `date` prints a literal `N`.

The CI job names are also unclear. The Linux job is named `BATS Tests` with the id `test`, next
to `BATS Tests (macOS)` with the id `test-macos`. A reader of the checks list cannot tell from the
name alone that `BATS Tests` runs on Linux.

## 2. Rule

The test suite passes on the Linux and the macOS CI jobs. A test, a helper and a mock backend use
only command forms that GNU and BSD tools both accept, unless it first checks for the tool and
skips with a message when the form is missing, as `run_on_tty` does. A test's outcome does not
depend on the length of the temporary directory path or on how the C library words an error.
`ralph` does not change.

Each BATS job in CI names its platform, in its id and in its display name.

## 3. Behaviour

### Mock backends

- The committing mock ticks the first `- [ ]` line under `## Items`, or the first in the file
  when the plan has no `## Items` heading, and leaves every other line unchanged, on both
  platforms. It never ticks the template's exemplar, so each build iteration ships one item. Today
  on Linux it ticks the exemplar first; this spec changes that.
- Each build iteration of the committing mock still appends one line to `mock-build-output.txt`
  and commits it, so that every build moves `HEAD`.
- The mock in `review.bats` un-ticks exactly the one item the test names and nothing else.
- Each test or mock that edits a file in place gives the same result on both platforms and leaves
  no backup file behind in the workspace.

### Assertions

- The metrics tests that join the `iteration` values compare the same comma-joined list on both
  platforms.
- The card tests that compare a path under the config directory, both the `config:` row and the
  `prompt:` row, read a central config file at a path whose length does not depend on `TMPDIR`,
  so the card never cuts the row and the tests still compare it whole. A local config file still
  shows as `./ralph.yaml (local)`.
- The `-v` rejection tests still prove that `ralph build` and `ralph auto` exit 1, and that the
  message is `ralph: invalid option -- ` for `build` and `ralph auto: invalid option -- ` for
  `auto`, followed by `v` with or without quotes.

No test is deleted or skipped on macOS to reach green, and no test asserts less about `ralph` than
it does today beyond what this section allows.

### CI workflow

- In `.github/workflows/ci.yml`, the Linux BATS job has the id `test-linux` and the name
  `BATS Tests (Linux)`. Its steps do not change.
- The macOS job keeps the id `test-macos` and the name `BATS Tests (macOS)`.
- The `ShellCheck` job keeps its id and name. It runs once, on Linux, and checks the scripts, not
  a platform.

## 4. Documentation

- `CLAUDE.md` and `AGENTS.md`, under testing conventions: tests, helpers and mock backends use
  only command forms that GNU and BSD tools both accept, unless they first check for the tool and
  skip with a message when the form is missing. The rule names the forms this spec
  removes: in-place `sed` with no backup suffix, `sed` addresses that start at line `0`, `paste`
  with no file operand, and `date +%N`. It also says that an assertion never compares a whole card
  row that holds a path under the temporary directory, and never depends on the quotes in glibc's
  `getopt` message.

## 5. Testing

- `bats test/` passes on the `BATS Tests (Linux)` and `BATS Tests (macOS)` CI jobs.
- The checks list of a pull request shows `BATS Tests (Linux)` and `BATS Tests (macOS)`, and no
  check named `BATS Tests` alone.
- `bats test/` passes on Linux with `TMPDIR` set to a 50-character path, and again to a
  130-character path. On today's suite, the 50-character run fails the four config-card tests
  named in §1.
- ShellCheck stays clean over `test/*.bats` and `test/test_helper.bash`.
- The 25 tests named in §1 keep their names and their intent.

## 6. Accepted risks

- **Linux CI cannot catch a new GNU-only form.** A test written on Linux can use a GNU-only form
  again, and only the macOS job reports it. That job runs on pull requests to `main` and on
  pushes to `main`. A change pushed straight to `main` shows the failure only after it lands, and
  without branch protection the job does not block a merge. The guardrails rule in §4 tells the
  build agent to avoid the forms.
- **A fix can expose a `ralph` defect.** If a fixed test then fails because of `ralph`, the build
  marks its item `- [~]`, records the failure in `PROGRESS.md`, and a later spec owns the `ralph`
  change.
- **The macOS job still uses Homebrew `bash` and `gnu-getopt`.** Spec 027 accepts this; this spec
  does not change it.
- **The rename orphans the old check name.** Commits from before the rename show a `BATS Tests`
  check, and later commits show `BATS Tests (Linux)`. `main` has no branch protection today, so no
  required check names the old job. A branch protection rule added later must name the new jobs.

## 7. Out of scope

- Any change to `ralph`, including the width at which the card shortens a row.
- Support for `/bin/bash` 3.2 or the macOS `getopt`.
- A lint that finds GNU-only forms in the tests.
- Changes to `.github/workflows/ci.yml` beyond the job rename in §3, including its tools and
  steps.
