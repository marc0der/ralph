# The plan format

`specs/` says **what** to build. `IMPLEMENTATION_PLAN.md` says **how**. You rarely write a plan by hand, but knowing its rules helps you read one, and helps you write specs that plan well.

The plan is a work queue, not a scratchpad. Every line in it is an instruction or a pass/fail check. Outcomes and lessons go in `PROGRESS.md`, and decisions and their reasons go in `specs/`.

## An item

Every item has the same six fields, and nothing else:

```markdown
- [ ] **Retarget the polkit agent to the Sway session**
  Spec: `specs/plasma-sway-remnants.md` item 3
  Scope: Add a session-target option. Do not change the Plasma agent.
  Files: `modules/home/keyring-services.nix`, `hosts/neomorph/home.nix`
  Steps:
  1. Add `polkitSessionTarget` to `keyring-services.nix`. Default it to `graphical-session.target`.
  2. Set `polkitSessionTarget` to `sway-session.target` in `hosts/neomorph/home.nix`.
  Done when: Two `NRestarts` reads 30 seconds apart return the same number.
```

## The rules

- **Small enough for one pass.** At most 150 words, 14 lines and 8 steps. An item that needs a ninth step gets split.
- **Steps point at things you can grep for:** names, option paths, literal values, files to copy an idiom from. Never line numbers or pasted code, because an item may run many commits after it was written.
- **`Done when` must be checkable by the agent.** A check that needs a fresh login or a human eye belongs in the spec's acceptance criteria. An item nobody can verify never completes.
- **Plain, strict English.** Items are written in [Simplified Technical English](https://www.asd-ste100.org/): one instruction per sentence, at most 20 words, active voice.
- **An optional final check.** If your `CLAUDE.md`, `AGENTS.md` or the goal names a full-verification command, the plan ends with one item that runs it over all the work. It cites `AGENTS.md verification gate` in place of a spec.

## Markers

| Marker  | Meaning |
|---------|---------|
| `- [ ]` | Open |
| `- [x]` | Shipped |
| `- [~]` | Superseded or blocked |

Only open items count towards the number of build passes.

## Who may change what

`plan` writes and reorders items freely. Once `build` starts, items are fixed: a build pass may only tick a box, mark an item `- [~]`, or add a new item at the end. If an item turns out to be wrong, the agent marks it `- [~]`, explains why in `PROGRESS.md`, and moves on. The next `plan` run writes the replacement.

`review` only adds items. It never re-opens a shipped one: if shipped code falls short of its spec, that becomes a new item. Each finding starts with its severity:

- **Critical:** under a reachable condition, however rare, the code behaves wrongly or fails a cited spec clause.
- **Major:** nothing is wrong yet, but a safety net is missing, so the next change is likely to break something unnoticed.
- **Minor:** the code misleads or burdens its reader.

Review needs a plan where every item has shipped, and a `.ralph/cycle-base` file, which the first `build` of the cycle writes. Otherwise it stops with an error. `plan` stops with an error when that file exists and the plan holds no `- [ ]` and no `- [~]` item, because that cycle was built and never archived.
