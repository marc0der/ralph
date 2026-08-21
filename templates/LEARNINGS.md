# Learnings

**Durable knowledge about this codebase. Edit in place — deduplicate, correct, and
delete what is no longer true. This is not a log; `PROGRESS.md` is the log.**

What belongs here: a fact you would want on your next iteration. What does not:
what one iteration did (`PROGRESS.md`), a decision and its reasoning (`specs/`), or
anything already obvious from reading the source.

Keep the whole file under about 300 lines. When it grows past that, merge
overlapping entries rather than appending. One line per learning, most relevant
first within each section.

## Patterns

How this codebase does things.

- e.g. "routing is registered in `app/routes.js`, one entry per resource — never inline in the handler"

## Gotchas

Traps that cost an iteration.

- e.g. "changing a migration means re-running `make seed`, or the fixture tests fail with no useful message"

## Context

Non-obvious facts about the system.

- e.g. "the audit table relies on index `idx_audit_ts` for this query pattern"
