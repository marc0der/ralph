---
id: "028"
created: 2026-11-24
area: [output]
related: ["027"]
---

# macOS Test Portability

Spec 027 added the `BATS Tests (macOS)` CI job and accepted that its first run might be red. It
is red: 25 of 795 tests fail on `macos-latest`, on every run since the job was added, while the
Linux job is green. Every failure lies in the test suite, not in `ralph`. The tests and their mock
backends call GNU-only command forms, and some assertions depend on the length of the temporary
directory or on the wording of glibc's `getopt` error. This spec makes the suite pass on both
platforms without changing what `ralph` does. It also names the Linux job for its platform, as the
macOS job already is.

## 1. Problem

The failures fall into five causes.

- **The shared committing mock cannot tick an item.** The mock in `test/test_helper.bash` ticks
  the first open item with a GNU-only `sed` edit that changes only the first match, using in-place
  editing with no backup suffix. BSD `sed` rejects it, so no item is ticked. Build never ships, the
  review guard skips phase 5, and every later phase reports a different state. Failing:
  `auto.bats` 17, 18, 19, 29, 72, 84, 86, 87, 90, 91 and `cards.bats` 172, 173.
- **Other in-place edits have no backup suffix.** `auto.bats:218`, `cards.bats:759` and the
  mock in `review.bats:332` edit a file in place with no suffix. BSD `sed` reads the script as
  the suffix and fails with `invalid command code`. `review.bats:332` also edits only the first
  match with the GNU-only form. Failing: 27, 201, 202, 698.
- **`paste` reads stdin with no file operand.** `metrics.bats:197`, `:227` and `:241` join lines
  with `paste` and no file operand. BSD `paste` needs `-` and prints its usage. Failing: 352, 354,
  355.
- **Card assertions depend on the temporary path length.** A macOS temporary directory sits under
  `/var/folders/…/T/`, which is much longer than `/tmp`. The central config path then makes the
  `config:` card row wider than the card, and the card shortens it, as it should. The tests
  compare the whole row with the full path, so they fail. The failure reproduces on Linux with a
  long `TMPDIR`. Failing: 150, 276, 297, 298.
- **Assertions match glibc's `getopt` wording.** `auto.bats:90` and `pipeline.bats:168` expect
  `invalid option -- 'v'`. Homebrew's `gnu-getopt` gets its message from the macOS C library,
  which does not put quotes around the option letter. Failing: 14, 447.

One more GNU-only form fails nothing today: the committing mock writes `date +%s%N` to make each
build's output line unique, and BSD `date` prints a literal `N`.

The CI job names are also unclear. The Linux job is named `BATS Tests` with the id `test`, next
to `BATS Tests (macOS)` with the id `test-macos`. A reader of the checks list cannot tell from the
name alone that `BATS Tests` runs on Linux.

## 2. Rule

The test suite passes on the Linux and the macOS CI jobs. A test, a helper and a mock backend use
only command forms that GNU and BSD tools both accept. An assertion holds for any temporary
directory path and does not depend on how the C library words an error. `ralph` does not change.

Each BATS job in CI names its platform, in its id and in its display name.

## 3. Behaviour

### Mock backends

- The committing mock ticks exactly the first open item of the plan and leaves every other line
  unchanged, on both platforms. A build iteration under it ships one item, as it does on Linux
  today.
- Each build iteration of the committing mock still appends a line that no earlier iteration
  wrote, so that every build moves `HEAD`.
- The mock in `review.bats` un-ticks exactly the one item the test names and nothing else.
- Each test or mock that edits a file in place gives the same result on both platforms and leaves
  no backup file behind in the workspace.

### Assertions

- The metrics tests that join the `iteration` values compare the same comma-joined list on both
  platforms.
- The config-card tests still prove the row names the central config file, the `(central)` label
  and the section, and that a local file shows as `./ralph.yaml (local)`. They pass whatever the
  length of the temporary directory path.
- The `-v` rejection tests still prove that `ralph build` and `ralph auto` exit 1, and that the
  message names the program, says the option is invalid, and names `v`. They do not depend on
  quotes around the letter.

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
  only command forms that GNU and BSD tools both accept. The rule names the forms this spec
  removes: in-place `sed` with no backup suffix, `sed` addresses that start at line `0`, `paste`
  with no file operand, and `date +%N`.

## 5. Testing

- `bats test/` passes on the `BATS Tests (Linux)` and `BATS Tests (macOS)` CI jobs.
- The checks list of a pull request shows `BATS Tests (Linux)` and `BATS Tests (macOS)`, and no
  check named `BATS Tests` alone.
- `bats test/` passes on Linux with `TMPDIR` set to a directory whose path is at least as long as
  a macOS one, such as `/tmp/…/q2/p1t6rgx8abcdefghijklmnopqrst0000gn/T`.
- ShellCheck stays clean over `test/*.bats` and `test/test_helper.bash`.
- The 25 tests named in §1 keep their names and their intent.

## 6. Accepted risks

- **Linux CI cannot catch a new GNU-only form.** A test written on Linux can use a GNU-only form
  again, and only the macOS job reports it. That job runs on every push and pull request, so the
  failure shows before merge. The guardrails rule in §4 tells the build agent to avoid the forms.
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
