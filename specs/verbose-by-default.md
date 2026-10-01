# Verbose by Default

Follow-up to `specs/verbose-live-streaming.md`. That spec gave `plan` and `build` live per-event
rendering, gated on `-v` / `--verbose`. This spec makes that output the default and adds
`-q` / `--quiet` to turn it off.

## 1. Problem

A real iteration lasts tens of minutes. Without `--verbose`, the operator sees the iteration banner,
then nothing until the iteration ends. The live stream is the only way to tell a working agent from a
stuck one, so every interactive run wants it. The operator must remember to pass `-v` on every
`plan`, `build`, `review` and `auto` call, and a run started without it cannot be switched on.

## 2. Rule

Verbose output is the default for `plan`, `build`, `review` and `auto`. `-q` / `--quiet` turns it off.

- **Default.** A run without `--quiet` behaves as a run with `--verbose` behaves before this change:
  live rendering, the backend command, exit codes, raw stream pointer or raw dump, push output and
  stderr markers. The one difference is the line prefix (§3).
- **No live filter.** `codex` and `copilot` ship an empty `BACKEND_JQ_LIVE`, so they render nothing
  live, and before this change `--verbose` dumped their whole raw stream after every pass. That dump
  does not become their default. Without `--quiet`, a backend with an empty `BACKEND_JQ_LIVE` prints
  `Raw stream: <path>` when the run retains the stream and `Raw stream not retained` otherwise, as a
  backend with a live filter does. A live filter that fails at run time keeps its raw dump fallback.
- **Quiet.** A run with `--quiet` prints the same lines as a run without `--verbose` before this
  change, except the two hints in §6. `--quiet` suppresses nothing more. Banners, summaries, warnings, errors and backend stderr
  stay visible.

## 3. The `[verbose]` prefix is removed

Each marker line that `--verbose` gated carries a `[verbose] ` prefix today. Once that output is
the default, the prefix labels nothing: it names a mode that no longer exists. Ralph drops the prefix
and keeps the rest of each line. Its other stderr lines (`Error:`, `Warning:`, `Hint:`) carry no
bracketed prefix either.

| Today | After |
|-------|-------|
| `[verbose] === Backend stderr ===` | `=== Backend stderr ===` |
| `[verbose] === End backend stderr ===` | `=== End backend stderr ===` |
| `[verbose] Backend command: …` | `Backend command: …` |
| `[verbose] Raw stream: <path>` | `Raw stream: <path>` |
| `[verbose] Raw stream not retained` | `Raw stream not retained` |
| `[verbose] Raw backend output:` | `Raw backend output:` |
| `[verbose] Raw stream unavailable: <path>` | `Raw stream unavailable: <path>` |
| `[verbose] Exit codes — backend: N, jq: N` | `Exit codes — backend: N, jq: N` |
| `[verbose] Push output:` | `Push output:` |

No `[verbose]` string remains in `ralph`.

## 4. `--verbose` is removed

`-v` and `--verbose` leave the `getopt` specs of `cmd_loop` and `cmd_auto`. Passing either fails
with exit 1 and `getopt`'s own message: `ralph: unrecognized option '--verbose'` for the long form
and `ralph: invalid option -- 'v'` for the short form. Under `auto` the prefix is `ralph auto:`. Ralph keeps no no-op alias: a flag with no effect
misleads its reader, and one switch is easier to reason about than two.

The `--verbose` argument inside the `claude` backend's `BACKEND_CMD` is a `claude` CLI flag that
`--output-format=stream-json` requires. It is not Ralph's flag and stays.

## 5. Internal state

`cmd_loop` and `cmd_auto` replace the local `verbose=false` with `quiet=false`, set to `true` by
`-q|--quiet`. Each existing `$verbose` test becomes `! $quiet`, and each `! $verbose` becomes
`$quiet`. No other control flow changes.

## 6. Hints

Two failure hints advise `--verbose` today, and only when it is off:

| Failure | Today, without `--verbose` | After, with `--quiet` |
|---------|----------------------------|-----------------------|
| Backend exit, stream not retained | `…, or --verbose for full diagnostics` | `…, or re-run without --quiet for full diagnostics` |
| jq parse failure, stream not retained | `Hint: re-run with --verbose to see raw backend output before jq processing` | `Hint: re-run without --quiet to see raw backend output before jq processing` |

Without `--quiet`, neither hint names a flag, which matches today's behaviour under `--verbose`.

## 7. `auto`

`auto` accepts `-q` / `--quiet` and forwards `-q` to the `plan`, `build` and `review` children, in the
`child_flags` position that `-v` holds today. `archive` and `init` take no such flag and stay bare.
Without `--quiet`, `auto` forwards nothing, and its children run verbose by their own default.
`auto` is verbose by default on purpose: an unattended run's log is where the live stream is read
after the fact.

The `--dry-run` child command lines show `-q` when `--quiet` is passed, because they print
`child_flags`.

`.ralph/auto-state` records no flags today, and this spec adds none. A `--resume` runs verbose unless
the operator passes `--quiet` again, as with `--skip-push`, `-m` and `-b`.

## 8. Other commands

`sandbox`, `init`, `archive`, `clean`, `metrics` and `version` have no verbose output. Each exits 1
with an error to stderr when passed `-q` or `--quiet`. Only `plan`, `build`, `review` and `auto`
accept the flag.

Today `sandbox` and `init` already reject an unknown option. `archive`, `clean` and `version` parse
no arguments and ignore it, and `metrics` reads it as a file path. Those four gain the refusal
`Error: '<command>' does not accept --quiet.`

## 9. Text

- **`usage`.** Replace the `-v, --verbose` line with
  `-q, --quiet          Don't stream backend activity; hide commands, exit codes and the raw stream path`.
- **`README.md`.** Replace the `-v`, `--verbose` row of the options table with
  `` | `-q`, `--quiet` | Don't stream the agent's activity live | ``.
- **`README.md`, "Watching a run".** Replace the first paragraph with: "A run shows the agent work as
  it happens: one line per tool call and per message. Add `-q` for one line per pass. (Codex and
  Copilot show only the path to the raw output.)"
- **`CLAUDE.md` and `AGENTS.md`.** Core loop step 6 reads "Under `--verbose` the stream is also teed".
  Change it to "Unless `--quiet` is passed, the stream is also teed".
- **Comments.** Code comments in `ralph` and the tests that name `--verbose` as Ralph's flag name
  `--quiet` or the default instead, so no comment describes a flag that no longer exists.

`specs/verbose-live-streaming.md` is a chronological record and does not change.

## 10. Tests

- Every existing test that passes `--verbose` or `-v` to `ralph` drops the flag and keeps its
  assertions, so it now proves the default. The exceptions are the three flag acceptance tests, whose
  only assertion is a zero exit; the new `-q` / `--quiet` acceptance tests replace them.
- An absence assertion on old hint text (`--verbose for full diagnostics`, `re-run with --verbose`)
  runs under `--quiet` and asserts the absence of the §6 text instead.
- Every assertion on a `[verbose] …` line asserts the unprefixed line from §3 instead.
- Every existing test that asserts the absence of verbose output, or the presence of a `--verbose`
  hint, passes `--quiet`. An absence assertion names the specific lines from §3 it excludes, since
  no shared marker remains, and a hint assertion checks the new text from §6.
- New: `--verbose` and `-v` exit 1 for `build` and `auto`, with the `getopt` messages from §4.
- The tests that pin the raw dump for `-b codex` without a live filter assert `Raw stream: <path>`
  or `Raw stream not retained` instead, and assert that no `Raw backend output:` line and no raw event
  body appears. `README.md` states the same for Codex and Copilot (§9).
- New: each of `sandbox`, `init`, `archive`, `clean`, `metrics` and `version` exits 1 on `--quiet`
  and on `-q`.
- New: `-q` and `--quiet` are accepted by `plan`, `build` and `review` under `--dry-run`.
- New: `auto -q` forwards `-q`: no `Backend command:` line appears on a full run, and the `--dry-run`
  child command lines contain `-q`.
- New: `auto` without `--quiet` shows `Backend command:` lines, replacing
  `-v reaches children: [verbose] markers appear on the output`.

## 11. Out of scope

- An environment variable or config file setting for the default.
- A quieter mode than today's non-verbose output.
