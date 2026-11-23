---
id: "025"
created: 2026-11-23
area: [config, backend, plan]
amends: ["019", "020"]
---

# Claude Phase Defaults

With no `model` or `effort` set, every phase runs the backend's default model, `opus` for
`claude`, at the backend's default effort. The plan cap is 6. Tuned runs show that each phase has
its own best setting, and that a plan rarely gains anything after its third pass. This spec gives
the `claude` backend built-in model and effort defaults for each phase, and lowers the plan cap to
3. The shipped `templates/config.yaml` states these defaults in its comments and uses Claude
examples in every section.

It amends `019-phase-config.md` §4, where the built-in default of `model` is
`BACKEND_DEFAULT_MODEL`, the built-in default of `effort` is "none", and the plan cap is 6, and
§11, where the shipped file's comments describe those defaults. It amends
`020-config-template-location.md` only where its content rules repeat §11 of 019.

## 1. Problem

One `auto` lifecycle, with settings chosen per phase in `ralph.yaml`:

| Phase | Model/effort | Iterations | Cost | Outcome |
|-------|--------------|------------|------|---------|
| plan | opus/max | 4 (4th changed nothing) | $19.30 | Passes 2 and 3 each fixed one compile gap a build would have hit for cents |
| build | sonnet/xhigh | 9 | $4.24 | 9/9 items, one iteration each |
| review | opus/xhigh | 1 | $2.46 | Two real findings; opus/max cost $40 on an earlier run |
| fix | opus/high | 3 | $0.96 | 2/2 items |
| retro | opus | 1 | $0.46 | Learnings updated |

An earlier opus/xhigh plan converged in 2 passes for $2.87. Without a config file, Ralph runs every
phase on opus at the CLI's default effort. That is more than build needs and less than review
needs. And a plan may run 6 passes when 3 are enough.

## 2. Rule

- **Built-in phase defaults for `claude`.** When the resolved backend is `claude`, a phase with no
  `model` or `effort` from the CLI or the file takes these values:

  | Section | Model | Effort |
  |---------|-------|--------|
  | `plan` | `opus` | `xhigh` |
  | `build` | `sonnet` | `xhigh` |
  | `review` | `opus` | `xhigh` |
  | `fix` | `opus` | `high` |
  | `retro` | `opus` | none: Ralph passes no flag |

- **Other backends** keep their current defaults: `BACKEND_DEFAULT_MODEL`, and no effort flag.
- **The plan cap is 3.** `PLAN_DEFAULT_CAP` becomes 3. Convergence still ends a plan early, and
  `-n` or `plan.iterations` still replaces the cap.
- **The template stays inert.** The shipped file still sets no `model` and no `effort`. It still
  carries only active values equal to the built-in defaults, so `-b codex` still runs with no
  dropped-keys warning.

## 3. Behaviour

### Resolution

Precedence for `model`, highest first:

1. `-m`
2. the file's `model` for the section, then `defaults.model`, subject to 019 §5
3. the backend's phase default for the section, when it has one
4. `BACKEND_DEFAULT_MODEL`

`effort` follows the same order, without step 4. A `defaults.model` or `defaults.effort` in the
file still reaches every phase, and beats the phase defaults.

`backend_claude` declares the phase defaults beside `BACKEND_DEFAULT_MODEL`. The other
`backend_<name>` functions declare none. `cmd_loop` applies them after `resolve_backend` and
before `require_effort_level`, so a phase default passes the same level check as a configured
effort.

A `-b` that differs from the file's backend drops the file's backend-tied keys, as today (019 §5).
The phase defaults then come from the backend `-b` names, so `-b claude` over a codex file gets
the claude phase defaults, and `-b codex` gets none.

### Visibility

The `Config:` block and each `metrics.jsonl` record show the resolved values, as they do today.
A plan with no config prints `backend=claude model=opus effort=xhigh` and `iterations=3`.

### `templates/config.yaml`

- The header keeps its sentence "The active values below equal the built-in defaults."
- `defaults.model` and `defaults.effort` stay commented. Their `Unset:` lines say that the phase's
  built-in default applies, and name where to find it.
- Each phase section keeps `model` and `effort` commented. Its `Unset:` lines state the phase
  default, for example `Unset: the defaults model applies, else opus for claude.` The commented
  example values are the `claude` phase defaults from §2.
- `review`'s commented examples change from `codex` / `gpt-5-codex` / `xhigh` to `claude` /
  `opus` / `xhigh`, so every section uses Claude examples.
- `plan`'s commented `iterations` example changes from 6 to 3.

## 4. Documentation

- `README.md`: the config key table's `model` and `effort` rows name the claude phase defaults,
  and the plan description says the cap is 3.
- `CLAUDE.md`: the command table's `plan` row says "max 3 iterations", and core loop step 2 names
  the claude phase defaults.
- `ralph --help` names the plan cap where it names it today.

## 5. Testing

`test/config.bats` unless stated otherwise.

- With no config file and the `claude` backend, each of `plan`, `build`, `review`, `fix` and
  `retro` prints the model and effort of §2 in its `Config:` block. `retro` prints
  `effort=default`.
- `-m` and `-e` beat the phase defaults. A section `model` beats them, and so does a
  `defaults.model`.
- With `backend: codex` in the file, `build` prints codex's `BACKEND_DEFAULT_MODEL` and
  `effort=default`.
- `-b claude` over a file with `backend: codex` prints the claude phase defaults.
- The built backend command carries `--effort xhigh` for a `plan` with no effort set.
- `test/pipeline.bats`: a plan with no `-n` and no `iterations` prints a cap of 3.
- `templates/config.yaml` has no uncommented `model:` or `effort:` line, and every commented
  `backend:` example reads `claude`.
- The install test that compares the installed file with `templates/config.yaml` still passes.

## 6. Accepted risks

- **Built-in model names age.** `opus` and `sonnet` are aliases the claude CLI resolves, so they
  follow new releases. A model that loses an alias needs a Ralph release.
- **A plan that needs more than 3 passes stops with gaps.** The build that follows reaches the gaps
  at compile time or files them as new items, and `plan.iterations` raises the cap.
- **One lifecycle is thin evidence.** These defaults come from a few tuned runs. Every value can be
  overridden per phase in `ralph.yaml`.

## 7. Out of scope

- Phase defaults for `codex`, `copilot` and `pi`.
- Changing `BACKEND_DEFAULT_MODEL` for any backend.
- Per-phase defaults for `extra_args` or any neutral key other than the plan cap.
