# Phase Config

Ralph takes its per-run settings from CLI flags only. This spec adds a YAML file that sets the
backend, model, effort, iteration count and loop tuning for each phase. The file resolves the same
way as the prompt files: a central copy, with an optional local copy in the workspace.

## 1. Problem

Every phase runs with the same backend and model unless the operator passes `-b` and `-m` on each
command. Several settings cannot be changed at all:

- No backend gets an effort level. Each CLI uses its own default.
- The build headroom (20%) and the noop patience (2) are hard-coded.
- `auto` forwards one `-b` and one `-m` to every child, so plan, build and review cannot use
  different models in one lifecycle.
- `auto` runs build twice: phase 4 builds the plan, and phase 6 fixes the review findings. Both
  runs use the same settings.

## 2. Files and resolution

| Copy | Path | Written by |
|------|------|------------|
| Central | `$CONFIG_DIR/config.yaml` (`~/.config/ralph/config.yaml`) | `install.sh`, every install |
| Local | `./ralph.yaml` at the workspace root (`$PWD`) | the operator, or `ralph init --config` |

Resolution is a whole-file override, the same as `resolve_prompt`:

1. If `./ralph.yaml` exists, Ralph reads it and ignores the central copy.
2. Otherwise, if the central copy exists, Ralph reads it.
3. Otherwise, Ralph uses the built-in defaults and needs no YAML parser.

A key that the winning file leaves out takes its built-in default. The central copy never fills a
gap in the local copy.

Precedence for each setting, highest first: CLI flag, then the winning file, then the built-in
default.

## 3. Parser

Ralph parses the file with mikefarah `yq` v4. It converts the file to JSON once
(`yq -o=json`), and jq does the rest.

- Ralph needs `yq` only when §2 finds a file. After an install, the central copy always exists,
  so in practice `yq` is a dependency of every `plan`, `build`, `fix` and `review`.
- Ralph checks that `yq --version` names `mikefarah` and major version 4. The Python `yq` wrapper
  uses the same binary name and different syntax. On failure, Ralph prints the file it tried to
  read and exits 1:

  ```
  Error: ralph.yaml needs mikefarah yq v4 (https://github.com/mikefarah/yq); found: <version line or 'none'>.
  ```

- The Dockerfile installs a pinned mikefarah `yq` v4 binary.

## 4. Schema

### Sections

The file holds at most five top-level sections, each a map: `defaults`, `plan`, `build`,
`review`, `fix`. Each section is optional, and an empty file is valid.

- `plan`, `build`, `fix` and `review` configure the commands of the same name.
- `fix` configures `ralph fix`, which `auto` runs in phase 6 (§7). It is a peer of `build` and
  does not inherit from it.
- Each phase section inherits from `defaults` key by key, subject to §5.

### Keys

| Key | Type | Kind | Phases | Built-in default | CLI flag |
|-----|------|------|--------|------------------|----------|
| `backend` | one of `claude`, `codex`, `copilot`, `pi` | backend | all | `claude` | `-b` |
| `model` | non-empty string | backend-tied | all | `BACKEND_DEFAULT_MODEL` | `-m` |
| `effort` | a level the backend lists (§6) | backend-tied | all | none: Ralph passes no flag | `-e` |
| `extra_args` | list of strings | backend-tied | all | `[]` | none |
| `metrics` | boolean | neutral | all | `true` | `--no-metrics` / `--metrics` |
| `quiet` | boolean | neutral | all | `false` | `-q` / `--verbose` |
| `iterations` | positive integer | neutral | plan, build, fix | none: see below | `-n` |
| `headroom_pct` | non-negative integer | neutral | build, fix | `20` | none |
| `noop_patience` | positive integer | neutral | build, fix | `2` | none |
| `skip_push` | boolean | neutral | build, fix | `false` | `--skip-push` / `--push` |

A key or a section with a null value (`model:` or `review:` and nothing after it) counts as
absent.

`defaults` may hold only the keys whose Phases column reads "all". A key in `defaults` reaches
every phase, so a key that is invalid for one phase is invalid in `defaults`.

### `iterations`

`iterations` behaves exactly like `-n`:

- In `plan`, it replaces the cap of 6. Convergence still ends the run early.
- In `build` and `fix`, it replaces the calculated count and turns off the noop exit.
- In `review`, it is a validation error, for the reason `-n` is: review runs one pass.

`headroom_pct` and `noop_patience` size and stop the self-sizing build. `iterations` turns that
behaviour off, so a section that sets `iterations` together with either of them is a validation
error.

With `headroom_pct` set, the build count becomes `ceil(open items * (100 + headroom_pct) / 100)`.
With `noop_patience` set, build stops after that many consecutive iterations in which no
repository moved.

## 5. Backend-tied keys

`model`, `effort` and `extra_args` belong to the backend they were written for. A value that is
right for one backend is usually wrong for another (`opus` is not a codex model). One rule
applies in two places.

### Inside the file

When a phase section sets a `backend` that differs from the backend `defaults` resolves to, which
is `defaults.backend` when set and the built-in `claude` otherwise, the phase inherits none of the backend-tied keys from `defaults`. It uses its own
backend-tied keys, and the built-in defaults for the rest. Ralph prints nothing: the file states
the change.

The neutral keys inherit as usual.

### On the command line

When `-b` names a backend that differs from the backend the file resolves for the phase, Ralph
drops the file's `model`, `effort` and `extra_args` for that phase and prints one warning to
stderr per dropped set:

```
Warning: -b codex overrides config backend 'claude' for build; dropped model 'opus', effort 'max'.
```

The warning names only the keys the file set. With no backend-tied key set, Ralph prints no
warning. `-m` and `-e` given on the command line still apply, because they were written for the
backend that `-b` names.

## 6. Effort

Ralph passes the value unchanged to the backend's own flag:

| Backend | Flag | Levels |
|---------|------|--------|
| claude | `--effort <level>` | low, medium, high, xhigh, max |
| codex | `-c model_reasoning_effort=<level>` | minimal, low, medium, high, xhigh, max, ultra |
| copilot | `--reasoning-effort <level>` | none, minimal, low, medium, high, xhigh, max |
| pi | `--thinking <level>` | off, minimal, low, medium, high, xhigh |

Each `backend_<name>` function declares `BACKEND_EFFORT_LEVELS` and passes the effort to
`build_backend_cmd` beside the model. When no effort is set, `build_backend_cmd` adds no flag, and
the backend's own default applies.

Ralph checks the effort against the resolved backend's `BACKEND_EFFORT_LEVELS` before the loop
starts, whether it came from the file or from `-e`:

```
Error: effort 'max' is not a pi level; use one of: off minimal low medium high xhigh.
```

The levels in the table are what the installed CLIs report on 2026-10-14. `claude --help` and
`copilot --help` list their levels. `pi --help` lists `off, minimal, low, medium, high, xhigh` and
no `max`.

The codex levels come from the binary, not from its help. `codex exec -c
model_reasoning_effort=bogus` starts a thread without complaint, so codex validates the value
server-side and against the model, never locally. Ralph therefore owns the list alone. The
`ReasoningEffort` variants in the `codex` binary are `minimal`, `low`, `medium`, `high`, `xhigh`,
`max` and `ultra`. Ralph accepts all seven. A level the chosen model does not support fails at the
backend, which is the safer failure: a short list refuses a valid level and no flag can override
it.

## 7. `fix` and `auto`

`ralph fix` is an alias of `ralph build` that reads the `fix` section in place of `build`. It
uses the build prompt, the build gates (`require_open_items`), `.ralph/cycle-base` and pushing
exactly as `build` does. Only the config section differs. Its metrics records carry
`mode: build` and `section: fix`.

`ralph build` reads `build`. `auto` runs `ralph fix -y` in phase 6, so no environment variable
selects the section and nothing reaches the backend's process tree. The auto report names the
row `6 fix`.

`auto --dry-run` shows the phase 6 line as:

```
  6 fix       /path/to/ralph fix -y
```

`auto` forwards `-m`, `-b`, `-e`, `-q`, `--verbose`, `--metrics`, `--no-metrics`, `--skip-push`
and `--push` to its plan, build and review children, as it forwards flags today. A forwarded flag
overrides every section, `fix` included. `auto` still rejects `-n`. The file's `iterations` reaches
each child, because each child reads its own section.

`auto` validates the winning file, as §8 describes, before phase 1 and under `--dry-run`.

## 8. Validation

Ralph validates the winning file in `cmd_loop`, after `require_init_artifacts` and the hard stops,
and before `resolve_backend`. It validates the whole file, not only the section in use, so a typo
in `review` fails a `build`. Validation runs under `--dry-run` too.

Each of these is an error that names the file, the section and the key, and exits 1:

- The file is not valid YAML, or its top level is not a map.
- A top-level section other than the five in §4, or a section that is not a map.
- A key not in §4.
- A value of the wrong type or out of range.
- A key in a phase its Phases column excludes, including any key in `defaults` whose column does
  not read "all".
- `iterations` together with `headroom_pct` or `noop_patience` in one section.
- A `backend` not in `SUPPORTED_BACKENDS`.
- An `effort` not in the resolved backend's levels (§6), checked per section after §5.

Examples:

```
Error: ralph.yaml: build.noop_patiance is not a known key.
Error: ralph.yaml: review.iterations is not allowed; review runs one pass.
Error: ~/.config/ralph/config.yaml: defaults.skip_push is not allowed in defaults; set it under build or fix.
Error: ralph.yaml: build sets iterations with headroom_pct; iterations turns self-sizing off.
```

`extra_args` is not checked beyond its type. Its items go into the backend command after Ralph's
own arguments and before the prompt slot. For copilot, that means before the trailing `-p`. The
operator owns what an extra argument breaks.

## 9. CLI

New command `fix` (§7). It takes the same flags as `build`.

New flags on `plan`, `build`, `fix`, `review` and `auto`:

| Flag | Meaning |
|------|---------|
| `-e, --effort LEVEL` | Effort level for the run (§6) |
| `--verbose` | Stream backend activity; overrides `quiet: true` |
| `--metrics` | Record metrics; overrides `metrics: false` |
| `--push` | Push after each build iteration; overrides `skip_push: true` |

Each pair of opposites is an error when both are given: `-q` with `--verbose`, `--no-metrics`
with `--metrics`, `--skip-push` with `--push`. `--push` is accepted wherever `--skip-push` is, and
like it does nothing in plan and review.

`ralph init` gets `--config`:

- It copies `$CONFIG_DIR/config.yaml` to `./ralph.yaml` through `scaffold`, which refuses to
  overwrite an existing file.
- It fails as `--prompts` does when the central copy is missing.
- It combines with `--prompts`.
- `auto`'s init phase never passes it.

`ralph init` adds `ralph.yaml` to `.gitignore` on every run, as it adds the `PROMPT_*.md` files.
The local copy is personal.

`ralph.yaml` is not an artifact. `archive` and `clean` leave it in place.

## 10. Visibility

Each `plan`, `build`, `fix` and `review` run prints one `Config:` block to stderr before its first
iteration. It prints under `--quiet` and under `--dry-run` too:

```
Config: ./ralph.yaml (local) [fix]
  backend=claude model=sonnet effort=high
  iterations=auto(12) headroom=20% patience=2 push=on metrics=on quiet=off
```

- The source is `./ralph.yaml (local)`, the central path with `(central)`, or `built-in (no config
  file)`.
- The section in brackets is the one the run read: `plan`, `build`, `review` or `fix`.
- An unset effort prints as `effort=default`.
- In build, `iterations` prints as `auto(<count>)` when self-sizing, or as the number when fixed.
  Plan prints its cap. Review prints `iterations=1`. `headroom`, `patience` and `push` print only
  in build.
- `metrics` prints the effective value, so a dry run prints `metrics=off (dry-run)`.

Under `auto`, each child prints its own block, so a lifecycle prints one block per phase that runs,
at most four.

Each `metrics.jsonl` record gains three fields beside `backend` and `model`: `effort` (string or
null), `config` (the winning file's path, or null), and `section`. `ralph metrics` shows the new
fields in its per-run summary when they are present, and reads older records that lack them.

## 11. Installation

- `install.sh` copies `config.yaml` from the repository to `$CONFIG_DIR/config.yaml` on every
  install, overwriting the old copy, as it does for the prompts.
- The shipped file carries active values equal to the built-in defaults, with a comment on every
  key that states its type, phases and CLI flag.
- The shipped file leaves `headroom_pct`, `noop_patience` and `iterations` commented out at their
  default values, so adding `iterations` conflicts with no active key.
- The shipped file leaves `model`, `effort` and `extra_args` unset, each with a comment saying the
  backend's own default applies. Then `-b codex` runs with no §5 warning.
- The Dockerfile installs `yq` (§3).
- `install.sh` checks for mikefarah `yq` v4 and, when it is missing, prints
  `Warning: ralph needs mikefarah yq v4 to read config.yaml; install it or remove <path>.`

## 12. Documentation

- `README.md`: a "Customising" subsection on the config file, with the table from §4 and the
  resolution order from §2. The "Reference" section lists the new flags.
- `README.md` lists mikefarah `yq` v4 as a host prerequisite.
- `CLAUDE.md` and `AGENTS.md`: the core loop flow names config resolution and validation, and the
  installation layout names `config.yaml`. The sandbox paragraph lists `yq`.
- `CLAUDE.md` and `AGENTS.md`: the commands table lists `fix`.
- `usage`: the `fix` command, the new flags, and `init --config`.
- Code comments: one line where `cmd_loop` resolves the config.

## 13. Testing

Tests that need a parser skip with a message when mikefarah `yq` v4 is not on `PATH`.

### Resolution

- With no file, a run uses the built-ins, prints `built-in (no config file)`, and needs no `yq`.
- With only the central copy, a run uses its values and names it as the source.
- With both copies, a run uses only the local one. A key the local copy omits takes the built-in
  default, not the central value.
- A CLI flag beats the file for each flag in §9.

### Parser

- A file and no `yq` on `PATH` fails with the §3 error.
- A file and a fake `yq` whose `--version` lacks `mikefarah` fails with the §3 error.

### Schema and validation

- Each error class in §8 fails with exit 1 and names the file, section and key.
- Validation covers a section the run does not read.
- `--dry-run` validates.
- An empty file and a file with a null value pass.

### Backend-tied keys

- A phase that changes `backend` inherits no `model`, `effort` or `extra_args` from `defaults`,
  and prints no warning.
- `-b` to another backend drops the file's backend-tied keys and prints the warning, naming only
  the keys the file set.
- `-b` to another backend with `-m` given uses the `-m` model.

### Iterations and tuning

- `plan.iterations: 2` caps a non-converging plan at 2.
- `build.iterations: 3` runs 3 iterations through two noops, as `-n 3` does.
- `headroom_pct: 50` sizes a build of 4 open items at 6.
- `noop_patience: 3` stops a build after 3 consecutive noops, not 2.

### Effort

- Each backend's command carries its effort flag when effort is set, and no flag when unset.
- An effort outside the backend's levels fails before the first iteration, from the file and
  from `-e`.

### `auto`

- `ralph fix` reads `fix`, and `ralph build` reads `build`. Their `Config:` blocks show `[fix]`
  and `[build]`.
- `ralph fix` fails like `ralph build` when the plan holds no `- [ ]` item.
- Phase 6 runs `ralph fix`, and `auto --dry-run` shows `6 fix` with `ralph fix -y`.
- `auto -e high` reaches every child.

### Flags

- Each pair of opposites in §9 fails when both are given.
- `--verbose` overrides `quiet: true`; `--metrics` overrides `metrics: false`; `--push`
  overrides `skip_push: true`.

### Init, archive, clean

- `init --config` copies the central copy to `./ralph.yaml` and does not overwrite an existing
  one.
- `init --config` fails when the central copy is missing.
- `init` adds `ralph.yaml` to `.gitignore`.
- `archive` and `clean` leave `ralph.yaml` in place.

### Visibility and metrics

- The `Config:` block prints under `--quiet` and `--dry-run`, with source, section and values.
- Metrics records carry `effort`, `config` and `section`.
- `ralph metrics` reads a run whose records lack the new fields.

### Drift

One test guards the shipped file against the built-ins. It runs `--dry-run` for `plan`, `build`,
`fix` and `review` with the repository's `config.yaml` as the central copy, then again with no
config file. Each pair of `Config:` blocks must match, apart from the source label.

## 14. Accepted risks

- **A stale local copy.** Whole-file override means a local `ralph.yaml` does not pick up later
  changes to the central copy. The `Config:` block names the source, so the cause is visible.
- **`install.sh` overwrites central edits.** An operator who edits the central copy loses the edits
  on the next install. Personal settings belong in `./ralph.yaml`.
- **`extra_args` can break the stream.** An argument such as `--output-format text` breaks the
  parser. Ralph does not guard against it.
- **Effort levels drift.** A backend CLI can add or remove a level, and Ralph's list then refuses
  a valid level or passes an invalid one. The table in §6 needs upkeep.

## 15. Out of scope

- A key-level merge between the central and local copies.
- Shared team settings. Neither copy is meant to be committed.
- Multi-pass review. `review.iterations` stays an error.
- Per-backend sub-maps inside a phase section.
- A model column in `auto`'s lifecycle summary. The per-phase `Config:` blocks cover it.
- Settings for `sandbox`, `archive`, `clean` and `init`.
- A prompt path per phase. Prompts still resolve through `resolve_prompt`.
