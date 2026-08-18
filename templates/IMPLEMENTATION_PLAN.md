# Implementation Plan

**Prioritised index of work items. Order is priority — the build agent picks the top incomplete item.**

This file is an **index only** — one line per item, no detail. The detail for each
item lives in its own task file under `plan/`. That way every iteration can read
the whole queue cheaply and then read only the single task file it is about to
implement.

## Entry Format

This file holds three sections: this title, `## Entry Format`, and `## Items`. Never add another heading.

One bullet per item, on a single line, under `## Items` below:

```markdown
  - [ ] **Short imperative title** — one-line description of the outcome. → [NNN-short-slug.md](plan/NNN-short-slug.md)
```

(The example is indented so it isn't mistaken for a real entry — actual entries
start at column 0.)

`NNN` is a zero-padded sequence number, allocated in order and never reused. The
link target must be the item's task file.

Rules:

- Order is priority. The build agent picks the top incomplete item.
- Write at most 10 words per title. Write one line per entry.
- The index carries the title, the outcome and the link. Nothing else.
- Record no rationale, no evidence, no history, and no status. The task file and `PROGRESS.md` hold those.

Markers, matching the `**Status:**` in the task file:

- `- [ ]` open
- `- [x]` shipped
- `- [~]` superseded or blocked; never delete it — add a replacement item instead

Anchor every marker at column zero. Never nest one item under another.

## Task File Format

Each `plan/NNN-short-slug.md` holds the detail for exactly one item, in these
fields, in this order, and no others:

````markdown
# NNN. Short imperative title

**Status:** Not started

## Spec

`specs/file.md` item N

## Scope

What is included. What is excluded.

## Files

`path/to/file`, `path/to/other`

## Steps

1. Imperative technical instruction.
2. Imperative technical instruction.

## Done when

Criterion the agent can check without a human.

## Completion notes

_Filled in when the item ships: what shipped, test counts, and any deviation
with its tracking reference. Keep it to a few lines — the narrative belongs in
`PROGRESS.md`._
````

Rules:

- The spec states what to build. The task file states how to build it.
- Cite a spec file plus an item number or a section name in `Spec`.
- Write at most 150 words per task file, excluding the completion notes.
- Write at most 2 sentences for `Scope`. Write at most 2 sentences for `Done when`.
- Write at most 8 steps. Write one action per step. Write at most 20 words per step.
- Split any item that needs a ninth step. That item is too large for one iteration.
- Name symbols, option paths, literal values, and files to copy an idiom from.
- Never cite line numbers. Never paste code. Every named token must be greppable.
- List paths only in `Files`.
- Write every field in Simplified Technical English. Use active voice and present tense.

When the item ships, the build agent flips `**Status:**` to `Done`, writes the
completion notes here, and flips the index entry to `- [x]`. The notes stay in
the task file rather than the index, so the queue every iteration re-reads keeps
to one line per item.

## Items
