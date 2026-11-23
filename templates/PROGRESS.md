# Progress Log

**Append-only log of iterative work. Never edit or remove previous entries.**

## Entry Template

Each entry must follow this structure exactly:

Take the heading's time from `date '+%Y-%m-%d %H:%M'`. Its zone is the sandbox's `TZ`, which is fixed when the sandbox is built and is UTC unless the host exported `TZ`. On a run outside the sandbox it is the host's zone.

---

### [YYYY-MM-DD HH:mm] — [IMPLEMENTATION_PLAN.md item reference]

**Summary:** One-line description of what was done.

**Files changed:**
- `path/to/file` — brief reason

**Test outcome:** PASS | FAIL (with detail if failed)

**Learnings:**
- _Patterns:_ e.g. "this codebase uses X for Y"
- _Gotchas:_ e.g. "don't forget to update Z when changing W"
- _Context:_ e.g. "the audit table relies on index X for this query pattern"

---
