---
id: "029"
created: 2026-11-24
area: [config, backend]
amends: ["025"]
---

# Claude Phase Default Values

Corrective follow-up to `025-claude-phase-defaults.md`. Spec 025 gives the `claude` backend a
built-in model and effort for each phase. Its values for `review` and `retro` do not match the
settings the project runs with. This spec replaces the table in 025 §2, two clauses of 025 §3 and
the `retro` line in 025 §5. The rest of 025 stands.

## 1. Rule

When the resolved backend is `claude`, a phase with no `model` or `effort` from the CLI or the file
takes these values:

| Section | Model | Effort |
|---------|-------|--------|
| `plan` | `opus` | `xhigh` |
| `build` | `sonnet` | `xhigh` |
| `review` | `opus` | `max` |
| `fix` | `opus` | `high` |
| `retro` | `sonnet` | `medium` |

`review` changes from `xhigh` to `max`. `retro` changes from `opus` with no effort flag to `sonnet`
at `medium`. Every phase now passes an effort flag.

## 2. Testing

This replaces the first bullet of 025 §5: with no config file and the `claude` backend, each of
`plan`, `build`, `review`, `fix` and `retro` prints the model and effort of §1 on its run card.
`retro` prints `effort: medium`.

## 3. Visibility and template

This replaces two clauses of 025 §3:

- **Visibility.** A run shows the resolved values on its run card, and each `metrics.jsonl` record
  holds them. A plan with no config prints `model: opus effort: xhigh` and `iterations: 3` on its
  run card. Runs print no `Config:` block.
- **Template.** `review`'s commented examples in `templates/config.yaml` read `claude` / `opus` /
  `max`, the `review` defaults of §1.

## 4. Accepted risks

- **`max` review costs more.** Spec 025 records one opus/`max` review at $40, against $2.46 at
  `xhigh`. Review runs once per cycle and is the cycle's only gate, so the default favours depth.
  `review.effort` in `ralph.yaml` or `-e` lowers it.
