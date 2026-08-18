# Implementation Plan

**Prioritised index of work items. Order is priority — the build agent picks the top incomplete item.**

This file is an **index only** — one line per item, no detail. The detail for each
item lives in its own task file under `plan/`. That way every iteration can read
the whole queue cheaply and then read only the single task file it is about to
implement.

## Entry Format

One bullet per item, on a single line, under `## Items` below:

```markdown
  - [ ] **Short imperative title** — one-line description of the outcome. → [NNN-short-slug.md](plan/NNN-short-slug.md)
```

(The example is indented so it isn't mistaken for a real entry — actual entries
start at column 0.)

`NNN` is a zero-padded sequence number, allocated in order and never reused. The
link target must be the item's task file. Use `- [ ]` for incomplete and `- [x]`
for complete, matching the `**Status:**` in the task file.

## Task File Format

Each `plan/NNN-short-slug.md` holds the detail for exactly one item:

````markdown
# NNN. Short imperative title

**Status:** Not started

## Scope

What is included, and what is explicitly excluded (1-2 sentences).

## Files

`path/to/key/file`, `path/to/other/file` (optional — omit when obvious)

## Done when

Concrete verification criteria, referencing runnable commands where possible.

## Completion notes

_Filled in when the item ships: what shipped, test counts, and any deviation
with its tracking reference. Keep it to a few lines — the narrative belongs in
`PROGRESS.md`._
````

When the item ships, the build agent flips `**Status:**` to `Done`, writes the
completion notes here, and flips the index entry to `- [x]`. The notes stay in
the task file rather than the index, so the queue every iteration re-reads keeps
to one line per item.

## Items

