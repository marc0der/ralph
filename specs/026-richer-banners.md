---
id: "026"
created: 2026-11-23
area: [output, config, plan, build, review, retro]
amends: ["019", "023", "025"]
related: ["009", "018", "021", "024"]
---

# Richer Banners

Before its first iteration, a run prints two blocks. A header on stdout names the mode, backend,
prompt, branch, model, iteration cap, goal and metrics file. A `Config:` block on stderr names the
config source, backend, model, effort and tuning keys. The two blocks repeat backend and model, and
effort appears only in the second, in `key=value` form. Each iteration then opens with one divider,
`==== ITERATION 3 / 7 ====`, and closes with a `Metrics:` line when metrics are on.

This spec merges the two run blocks into one run card, gives each iteration a card that says what
the iteration works on, restyles the closing line to match, and adds colour on a terminal. It
amends `specs/019-phase-config.md` and replaces the block format in its section 10. The rest of
section 10, which covers the `metrics.jsonl` fields, is unchanged. Where
`specs/023-run-logs-and-metrics.md` §3 `cmd_loop` names the `Metrics:` banner line, and where
`specs/025-claude-phase-defaults.md` §3 Visibility names the `Config:` block, the run card carries
the same values.

## 1. Problem

An operator who scrolls back through a long build log sees this at the start of iteration 3:

```
====================================== ITERATION 3 / 7 ======================================
```

The divider does not tell the operator which item the iteration works on, which effort drives it,
how long the run has taken, or when the iteration started. To find the effort, the operator must
scroll back to a stderr block at the top of the run. To find the item, the operator must read the
agent's output.

## 2. Rule

- **One run card.** A run prints one run card before its first iteration. The run card holds every
  setting the run resolved except the goal. It replaces the stdout header and the `Config:` block.
- **One iteration card.** Each iteration opens with an iteration card: a divider line and a
  headline line. The divider names the settings that drive the iteration and the times. The
  headline names what the iteration works on.
- **One closing line.** Each iteration that ends without a failure closes with one footer line in
  the same style as the divider.
- **Colour on a terminal only.** Colour decorates text and never changes it. Output with the colour
  removed is the same as the output Ralph prints without colour.

## 3. Behaviour

### Width

The cards and the footer use one width per stream. On a terminal, the width is `COLUMNS` when it
is a positive integer, else the column count that the stream's terminal reports, capped at 120.
The cap applies to both sources. A terminal that reports no positive column count gets 120. Ralph
reads `COLUMNS` from its caller's environment only, and never lets the shell rewrite it during
the run.
The width is read for the stream the line goes to: stderr for the run card, stdout for the
iteration card and the footer. Off a terminal, the width is 120. A line longer than the width is cut
to the width, and its last character is `…`. No card line wraps. Every rule line, including the
divider and the footer, is padded with its rule character to exactly the width. A rule line that
holds text ends in a space and at least two rule characters. Those characters count toward its
length, also when Ralph checks whether the footer is longer than the width. The examples in
this spec are shortened. Width is measured in screen columns. Ralph measures it in a UTF-8
locale whatever the caller's locale is, and counts one column per character.

### Colour

Ralph uses colour on a stream only when all of these are true:

- the stream is a terminal;
- `NO_COLOR` is unset or empty;
- `TERM` is not `dumb`.

The choice is made for stdout and stderr separately, so `ralph build 2> log` keeps colour on
stdout. Rules print dim, labels print in one colour, values print in the terminal's default
colour, and the headline prints bold. This spec does not fix the label colour. A rule line prints
dim as a whole, the text in it included, so the divider and the footer print dim. A run card row
that is cut to the width prints without colour.

### Run card

The run card goes to stderr. It prints under `--quiet` and under `--dry-run`, as the `Config:` block
does today. It prints before the outside-a-container warning. For a `build` run:

```
━━ ralph build ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  backend:     claude   model: opus    effort: high
  config:      ./ralph.yaml (local) [build]
  branch:      feat/usage-limit-message
  prompt:      /home/marco/.config/ralph/prompts/build.md
  iterations:  auto(7)  headroom: 20%  patience: 2  push: on
  metrics:     on       .ralph/logs/feat-x-20261123-143200-4242/build/metrics.jsonl
  quiet:       off
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- The top rule carries the title `ralph <mode>`: `plan`, `build`, `fix`, `review` or `retro`.
- Each row starts with a label and a colon. These labels align in one column, so the first values
  line up. A later pair on the same row prints as `label: value`, with the colon after the label.
  Each value or pair after the first label is one cell, and cells align in columns across rows. A
  column is as wide as its longest cell on that card plus two spaces. A row's last cell sets no
  width. When a row would pass the width, its pairs move to one row each.
- `config` prints the source as section 10 of spec 019 defines it: `./ralph.yaml (local)`, the
  central path with `(central)`, or `built-in (no config file)`. The section the run read follows
  in brackets.
- `effort` prints `default` when unset.
- `iterations` prints as section 10 of spec 019 defines it. `headroom`, `patience` and `push` print
  only in `build` and `fix`.
- `metrics` prints the effective value: `on`, `off` or `off (dry-run)`. When it is `on`, the
  metrics file path follows, as `specs/023-run-logs-and-metrics.md` places it.
- `extra args` prints the section's `extra_args`, joined by spaces, only when the section sets
  any. A `-b` that drops the file's `extra_args` (spec 019 §5) leaves the row out, as it leaves
  them out of the backend command.
- The run card holds no goal. The plan headline carries it (see the iteration card).

Under `auto`, each child prints its own run card. `auto`'s own notices are unchanged.

### Iteration card

The iteration card goes to stdout, where the divider prints today. It prints under `--quiet` and
under `--dry-run`. A blank line comes before it.

```
── 3/7 ── claude · opus · high ── 14m05s ── 14:32 ─────────────────────────────────────────────
▶ next: Add usage limit message to build loop
```

The divider holds, in this order:

- the iteration number and the iteration cap, `3/7`;
- backend, model and effort, with `default` for an unset effort;
- the wall time since iteration 1 started, in the format of the footer's wall time, `0s` on
  iteration 1;
- the local clock time when the iteration starts, `HH:MM`.

The headline depends on the mode:

| Mode | Headline |
|------|----------|
| `build`, `fix` | `▶ next: <title>`, where the title is the first `- [ ]` item's title, without its bold markers |
| `build`, `fix`, no open item | `▶ next: no open item` |
| `plan` | `▶ goal: <goal>` |
| `review` | `▶ reviewing <N> shipped items against <M> cited specs` |
| `retro` | `▶ distilling <N> PROGRESS.md entries · <M> learnings on file` |

- Before the plan headline is cut, each run of whitespace in the goal, newlines included, becomes
  one space.
- The build headline is a prediction. The agent picks the item, and Ralph does not check its pick.
- Ralph reads the plan when the iteration starts, so a later iteration names the item that is first
  at that time.
- Review's `N` is the count of `- [x]` items, and `M` is the size of the anchor set
  (`specs/014-spec-anchored-review.md`). An empty anchor set prints `against no cited specs`.
- Retro's `N` is the count of dated `PROGRESS.md` entries, and `M` is the count of `- ` bullets
  under every heading of `.ralph/learnings.md`, counted as `Retro kept N learnings` counts them,
  0 when the file is absent.
- A count of 1 takes the singular noun: `1 shipped item`, `1 cited spec`, `1 PROGRESS.md entry`,
  `1 learning`.
- The exemplar entry under `## Entry Format` never counts as an item and never supplies a title.

### Footer

The footer replaces the `Metrics:` line, on stdout:

```
── 3/7 done ── 4m12s wall · 38s api · 22 turns · $0.81 · 2 commits (+80/-12) · Bash 14, Edit 6 ──
```

- With metrics on, the footer holds the figures today's `Metrics:` line holds, in the same order.
- With metrics off, the footer holds the wall time only: `── 3/7 done ── 4m12s wall ──`.
- When the metrics record for the iteration is not written, the footer holds the wall time only,
  as with metrics off.
- The footer prints after every check that can end the run: the backend exit, the plan, retro
  and review pass checks, and the push. An iteration that any of these ends, and a dry-run
  iteration, print no footer.
- When the footer is longer than the width, Ralph removes the whole tool list and its ` · `
  separator. If the footer is still longer than the width, Ralph cuts it at the width, ending
  in `…`.

## 4. Documentation

- `README.md` — any sample output or text that shows or names the header, the `Config:` block, the
  divider or the `Metrics:` line shows or names the new cards. A short note says that `NO_COLOR` turns colour off.
- `CLAUDE.md` — core loop flow step 2 names the run card in place of `print_config_block`'s
  `Config:` block, and step 5 or 6 names the iteration card and its headline.

## 5. Testing

Tests run off a terminal, so their output has no colour and a width of 120.

**Run card**
- A dry-run `build` prints one run card on stderr, and prints no `Mode:` header on stdout.
- The run card names backend, model and effort on one row, and prints `effort: default` when unset.
- The run card prints under `--quiet`.
- A section that sets `extra_args` prints an `extra args` row with them. A section that sets none
  prints no such row.
- `headroom`, `patience` and `push` print in `build` and `fix`, and not in `plan`, `review` or
  `retro`.
- The `config` row prints each of the three sources with its section.
- The shipped `config.yaml` still drifts from no built-in default. The drift test reads the run
  card's rows in place of the `Config:` block.
- Under `auto`, each phase that runs prints one run card.

**Iteration card**
- The divider prints `1/3`, `2/3`, `3/3` across a three-iteration run.
- The divider names backend, model and effort, the elapsed time `0s` on iteration 1, and a time
  that matches `HH:MM`.
- A build with two open items prints the first item's title, without bold markers, in its first
  headline.
- After the agent ticks the first item, the next headline names the second item.
- A build with no open item at the start of an iteration prints `▶ next: no open item`.
- The exemplar entry never supplies a title.
- `plan` prints `▶ goal: ` and the goal. A goal longer than the width ends in `…`.
- `review` prints the shipped count and the anchor-set size, and the singular forms for a count
  of 1.
- `retro` prints the entry count and the learnings count, and `0 learnings` with no learnings
  file.

**Footer**
- With metrics on, the footer holds today's metric figures.
- With `--no-metrics`, the footer holds the wall time only.
- When the metrics record is not written, the footer holds the wall time only.
- A failed iteration prints no footer.
- A footer longer than the width loses its tool list. A footer still longer than the width ends
  in `…`.

**Colour and width**
- Off a terminal, no output line holds an escape sequence.
- On a terminal with `NO_COLOR` unset and `TERM=xterm`, the divider holds an escape sequence.
- With `NO_COLOR=1` on a terminal, no output line holds an escape sequence.
- With `TERM=dumb` on a terminal, no output line holds an escape sequence.
- With stdout on a terminal and stderr off one, stdout holds escape sequences and stderr holds
  none.
- With `COLUMNS=60` on a terminal, no card line is longer than 60 characters.
- With `COLUMNS=60` on a terminal that reports 70 columns, no card line is longer than 60
  characters.
- With `COLUMNS` unset, the divider is exactly as wide as a 70-column terminal, and 120 wide on a
  terminal that reports 0 columns.
- Every test that needs a terminal skips with a message when it cannot give Ralph one.

## 6. Accepted risks

- **The build headline can be wrong.** The agent may pick another item, for example when the first
  item is blocked. The headline says `next`, not `now`, and the agent's output shows its pick.
- **Scripts that parse the `Config:` block break.** The format in section 10 of spec 019 was for
  people to read. Ralph's own drift test moves to the run card.
- **Box-drawing characters need a UTF-8 terminal.** Ralph already prints `━` and `⚠️`. `─`, `▶` and
  `…` are new. Only card and footer lines end a cut with `…`; other lines keep `...`.
- **The width can change during a run.** Each card reads the width when it prints, so a resized
  terminal gets a matching card at the next iteration. Earlier cards stay as printed. A caller that
  sets `COLUMNS` fixes the width for the whole run.
- **Wide characters count as one column.** Ralph counts one column per character. A CJK ideograph
  or an emoji takes two, so a title, goal or path that holds one can make its line pass the
  width.

## 7. Out of scope

- `ralph metrics` output.
- `auto`'s phase notices and lifecycle summary.
- Retro's promotion banner and review's `Review filed N findings` line.
- The live stream renderer and the backend stderr markers.
- Colour in any output other than the run card, the iteration card and the footer.
- A flag or config key to force colour on or off.
