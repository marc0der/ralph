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
- **Quiet.** A run with `--quiet` behaves exactly as a run without `--verbose` behaves before this
  change. `--quiet` suppresses nothing more. Banners, summaries, warnings, errors and backend stderr
  stay visible.

## 3. The `[verbose]` prefix is removed

Each diagnostic line that `--verbose` gated carries a `[verbose] ` prefix today. Once that output is
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
with the `getopt` unknown-option error and exit 1. Ralph keeps no no-op alias: a flag with no effect
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

The `--dry-run` child command lines show `-q` when `--quiet` is passed, because they print
`child_flags`.

`.ralph/auto-state` records no flags today, and this spec adds none. A `--resume` runs verbose unless
the operator passes `--quiet` again, as with `--skip-push`, `-m` and `-b`.

## 8. Other commands

`sandbox`, `init`, `archive`, `clean`, `metrics` and `version` have no verbose output and do not
accept `--quiet`.

## 9. Text

- **`usage`.** Replace the `-v, --verbose` line with
  `-q, --quiet          Don't stream backend activity; hide commands, exit codes and the raw stream path`.
- **`README.md`.** Replace the `-v`, `--verbose` row of the options table with
  `` | `-q`, `--quiet` | Don't stream the agent's activity live | ``.
- **`CLAUDE.md` and `AGENTS.md`.** Core loop step 6 reads "Under `--verbose` the stream is also teed".
  Change it to "Unless `--quiet` is passed, the stream is also teed".
- **Comments.** Code comments in `ralph` and the tests that name `--verbose` as Ralph's flag name
  `--quiet` or the default instead, so no comment describes a flag that no longer exists.

`specs/verbose-live-streaming.md` is a chronological record and does not change.

## 10. Tests

- Every existing test that passes `--verbose` or `-v` to `ralph` drops the flag and keeps its
  assertions, so it now proves the default.
- Every assertion on a `[verbose] …` line asserts the unprefixed line from §3 instead.
- Every existing test that asserts the absence of verbose output, or the presence of a `--verbose`
  hint, passes `--quiet`. An absence assertion names the specific lines from §3 it excludes, since
  no shared marker remains, and a hint assertion checks the new text from §6.
- New: `--verbose` and `-v` exit 1 with an unknown-option error for `build` and `auto`.
- New: `-q` and `--quiet` are accepted by `plan`, `build` and `review` under `--dry-run`.
- New: `auto -q` forwards `-q`: no `Backend command:` line appears on a full run, and the `--dry-run`
  child command lines contain `-q`.
- New: `auto` without `--quiet` shows `Backend command:` lines, replacing
  `-v reaches children: [verbose] markers appear on the output`.

## 11. Out of scope

- An environment variable or config file setting for the default.
- A quieter mode than today's non-verbose output.
