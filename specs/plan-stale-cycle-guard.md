# Plan Stale Cycle Guard

Follow-up to `specs/one-shot-review.md` §3. That spec made `.ralph/cycle-base` a cycle artifact that
`archive` and `clean` remove. This spec stops `plan` from starting a new cycle on top of a finished
one that was never archived.

## 1. Problem

A cycle ends when its artifacts are archived or cleaned. `auto` always archives first, but the
manual flow does not enforce that step. An operator who runs `plan`, `build` and `review`, then
runs `ralph plan -g <next goal>` without `ralph archive`, starts the next feature inside the old
cycle:

- `write_cycle_base` writes the base only when it is absent, so the next `build` keeps the old base.
- The next `review` reads every change since the old base as the cycle's work. It re-reads work
  that an earlier review already audited, and can file findings against it.
- The old shipped items stay in `IMPLEMENTATION_PLAN.md`, and their `Spec:` fields stay in the
  anchor set.

Nothing fails. The review is silently wider than the cycle.

## 2. Rule

`plan` refuses to run when `.ralph/cycle-base` exists and `IMPLEMENTATION_PLAN.md` holds no `- [ ]`
item.

That state means a finished cycle was never archived: build has written a base, and no work is
left. An open item means the cycle is still in progress, for example after review has filed
findings. Re-planning mid-cycle stays legal. Items marked `- [~]` do not count as open, so a plan of
only shipped and superseded items is refused.

## 3. Behaviour

The check is a hard stop in `cmd_loop`, beside the goal check. It runs after
`require_init_artifacts`, before backend resolution, and neither `-n` nor `--dry-run` bypasses it.
It prints to stderr and exits 1:

```
Error: .ralph/cycle-base belongs to a finished cycle: IMPLEMENTATION_PLAN.md holds no incomplete items.
Run 'ralph archive' (or 'ralph clean') to end that cycle before running 'ralph plan'.
```

`auto` needs no guard for this: phase 1 archives the base before phase 3 plans, and `--resume`
resumes at plan only when plan failed, before any build has written a base.

## 4. Testing

- `plan` fails with the error above when the base exists and every item is `- [x]`.
- `plan --dry-run` and `plan -n 1` fail the same way.
- `plan` fails when the base exists and the plan holds only `- [x]` and `- [~]` items.
- `plan` runs when the base exists and the plan holds a `- [ ]` item.
- `plan` runs when the plan holds no open items and no base exists.

## 5. Out of scope

- A flag to override the guard. `ralph archive` is the way to end a cycle.
- Changes to `build`, which keeps the first build's base by design.
