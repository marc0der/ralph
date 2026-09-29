# One-Shot Review

Corrective follow-up to `specs/spec-anchored-review.md`. That spec made review a spec-fidelity
auditor that repeats passes until one changes nothing. This spec makes review the cycle's
gatekeeper: one pass, three standards of equal weight, and a closed catalogue of defects. It
replaces sections 4 to 12 of `spec-anchored-review.md`, and keeps its section 3, the anchor set.
The decision to stop repeating passes is recorded in `docs/adr/0001-one-shot-review.md`. The terms
used here are defined in `CONTEXT.md`.

## 1. Problem

Review drops defects it finds.

The spec-anchored prompt ranks the three levels by standard: spec drift is `Critical`, a defect is
`Major`, and a rule violation is `Minor`. A cap of 10 open findings, filled worst-first, then turns
that ranking into a filter. Four more rules push findings out of the plan:

- An observation that fits no check goes to the final message, which is written to no file. In a
  headless loop nobody reads it.
- "Never judge the plan" reads as an exemption. The review of 2026-09-18 found that a failed plan
  loop let the build phase run anyway, and filed nothing, because "every step of the composition
  item was implemented as written, so it is a question for `plan`".
- `Major` gets one line of definition and no method of proof, while drift gets several paragraphs.
- A finding dropped by the cap "is found again by a later run". `auto` runs review once, so there is
  no later run.

The same review also found two tests weakened by the cycle and two claims about external behaviour
that no test confirms. Neither was filed.

The cause is convergence. Review repeats passes until a pass changes nothing, and most of the rules
above exist to keep pass 2 from churning. Pass 2 is the same reviewer with the same tree and the
same instructions, so it adds little, and the price of keeping it stable is a reviewer that stays
quiet.

## 2. Model

**Review is the cycle's gatekeeper.** It decides what must be fixed before the cycle's work counts
as done.

- **One pass.** A review phase runs exactly one pass. Repetition belongs to cycles, where a later
  review has something new to check: build's fixes. `auto` runs one cycle, so it reviews once.
- **Three standards of equal weight.** A finding measures the tree against a clause of a cited spec,
  a written rule, or code quality. No standard ranks above another.
- **Falsifiable findings.** Every finding names its standard and proves the tree fails it. This is
  the invariant both earlier specs rest on, and it survives unchanged. Its purpose is now signal,
  not convergence: a finding a second reviewer would not file is noise, and build spends an
  iteration on it.
- **Consequence ranks findings.** Severity measures what the defect does, whatever standard it
  breaks.

The ban on judging decomposition from `review-phase.md` §1 stands. "I would have split this item
differently" is still unfileable. What is lifted is the reading that a faithful implementation of a
flawed step is not a defect. **A defect in the cycle's work is a finding even when the code does
exactly what its item said.**

## 3. The cycle base

Review needs the exact code the cycle produced. Today nothing records it: the plan item schema and
the `PROGRESS.md` template carry no commit field, and the reviewer infers the range from `git log`.

Ralph records the **cycle base**, the `HEAD` of every repository in the workspace just before
build's first commit of the cycle.

- **File.** `.ralph/cycle-base`, one `<repo> <sha>` line per repository, in exactly the format
  `repo_state` prints. A repository with no commits records `-`.
- **Writer.** `cmd_loop` in build mode writes it before the first iteration, when the file is absent.
  A second build in the same cycle keeps the first build's base. A dry run writes nothing.
- **Lifetime.** `.ralph/cycle-base` joins `ARTIFACTS`, so `archive` moves it into
  `.ralph/<timestamp>/` with the plan and `clean` deletes it. A cycle ends when its artifacts are
  archived or cleaned.
- **The cycle's work** is every change between the base and `HEAD`, in every repository the base
  lists. A repository absent from the base, or recorded as `-`, was created during the cycle, and
  all of its tracked files are the cycle's work.

Review reads the base and never writes it.

## 4. Standards

### Spec clauses

Unchanged from `spec-anchored-review.md` §3. The anchor set is the distinct `specs/` paths in the
plan's `Spec:` fields. Review reads each spec in the set whole, and reads no spec outside it. A
clause is in range whether or not an item decomposed it. The range is the whole tree. Review never
creates or edits anything under `specs/`.

An empty anchor set is legitimate. It means this cycle has no spec standard, and the other two
standards still apply.

### Written rules

Unchanged. Rules live in the rules directory the project's `AGENTS.md` or `CLAUDE.md` names,
resolved per repository. A project that names none produces no rule finding. Project conventions,
such as idioms, naming and layering, belong here and not in Ralph's catalogue.

### Code quality

A quality finding names one **finding kind** from the catalogue in section 5 and passes that kind's
test of proof. Nothing outside the catalogue is fileable as code quality.

The catalogue holds only kinds that are universal across projects, not mechanically detectable, and
in need of judgement or of a view across the whole cycle. Mechanical checks, such as function
length, complexity, magic literals, unused symbols and token-level clones, belong to the project's
linters and static analysis, which the verification command runs after every build item. Review
never re-checks what a linter owns.

## 5. The catalogue

| Kind | Test of proof |
|------|---------------|
| **Bug** | A reachable condition — inputs, state, an interleaving, a platform — and the wrong result the code produces under it. A failure path the code ignores counts. So does breakage in code the cycle did not touch, caused by code it did. |
| **Unverified assumption** | The code depends on an external behaviour — a tool, an API, a platform — that no test and no source in the workspace confirms, and it breaks if that behaviour is false. |
| **Weak test** | A test whose name claims a behaviour its assertions do not check, so it stays green when that behaviour is removed. |
| **Untested behaviour** | A behaviour the cycle added or changed that no test fails on when it is altered. The finding names the behaviour and the test file it belongs in. |
| **Vacuous assertion** | An assertion that cannot fail: a value compared to itself, a match that always succeeds, an exit code the harness forces. |
| **Cross-item duplication** | Two locations that solve the same problem, at least one written by the cycle. The finding names both and the place the shared version belongs. |
| **Misleading text** | A name, message or doc line that contradicts what the code does. The finding quotes both. |
| **Stale docs** | A document that still states behaviour the cycle changed. The finding quotes the stale line and states the new behaviour. |
| **Needless comment** | A comment the cycle added that restates the code, narrates history, or stands in for a better name, so deleting it or renaming loses nothing a reader needs. A one-line *why* the code cannot express is exempt. |

## 6. Range

- **Spec clauses** — the whole tree, as section 4 states.
- **Rules and code quality** — defects the cycle's work causes, wherever they show. A finding must
  trace to a change between the base and `HEAD`, and it may surface in code the cycle did not touch.
  Duplication the cycle introduced is in range even when the other copy predates the base. A defect
  that predates the base and no change touches is out of range.
- **A red suite.** Review runs the full verification command the guardrails name. A failure produces
  one finding for the whole cycle that names the failing tests. Never file one per item.

## 7. Severity

| Level | Definition | Typical kinds |
|-------|------------|---------------|
| **Critical** | Under a reachable condition, however rare or latent, the code produces wrong behaviour or fails a cited spec clause. | Bug, unmet spec clause, red suite |
| **Major** | Nothing is shown to be wrong today, but a safety net is missing, so the next change is likely to break something unnoticed. | Weak test, Untested behaviour, Vacuous assertion, Unverified assumption, Cross-item duplication, Stale docs |
| **Minor** | The code misleads or burdens its reader. | Misleading text, Needless comment |

A rule violation takes the level of its consequence: `Critical` when it produces wrong behaviour,
otherwise `Minor`. "Typical kinds" is a default, and a finding moves up when its consequence is
worse: stale help text that makes a user run a destructive command is `Critical`.

A latent `Critical` proves itself by argument, not reproduction. A race names the two operations and
the order that breaks them. A reproduction is welcome and never required.

The level is the first word of the title, followed by a colon, as today.

## 8. Filing

- **No cap.** Review files every finding that passes its test, and drops none for count.
- **Grouping.** Several instances of one `Major` or `Minor` kind merge into one item, inside the
  item limits of the plan contract. Every `Critical` is its own item.
- **Order.** Findings are appended below the last item, `Critical` first, then `Major`, then `Minor`.
- **Append only.** Review never edits, reorders, ticks, un-ticks or supersedes an item. An item build
  marked `[~]` gets no special rule: if the tree still fails the standard, that is an ordinary
  finding, and it routes around the blocker the `PROGRESS.md` entry records.
- **Schema.** A finding is an ordinary item with the six fields, the limits and the Simplified
  Technical English of the plan contract. The `Spec` field names the standard:
  - a spec clause: `specs/file.md` plus an item number or a section name
  - a rule: the rule file plus the rule name
  - a catalogue kind: `review catalogue` plus the kind name, such as `review catalogue, Weak test`
  - a red suite: `AGENTS.md verification gate` or `CLAUDE.md verification gate`

None of the last three forms contains `specs/`, so none enters the anchor set.

## 9. The review entry

Review appends exactly one entry to `PROGRESS.md`, following its template, with the item reference
`Review`. The entry carries:

- the coverage line: `Reviewed N of M specs and X of Y changed files.` Both pairs must match.
- **Out of range** — defects that predate the base, each with its location and scenario.
- **Unresolved** — spec contradictions and questions review could not settle from the tree.
- `No cited specs this cycle.` when the anchor set is empty.

A preference, and a finding that failed its test, is recorded nowhere. The final message repeats
the coverage line. Nothing else review notices goes only to the final message.

## 10. Lenses

The pass examines the cycle's work through four **lenses**, one per group of standards:

1. **Spec fidelity** — every spec in the anchor set, read whole, against the whole tree.
2. **Correctness** — Bug and Unverified assumption.
3. **Tests** — Weak test, Untested behaviour and Vacuous assertion.
4. **Text and structure** — Cross-item duplication, Misleading text, Stale docs, Needless comment,
   and the written rules.

The main context first lists the changed files from the base and reads the anchor set and the rules.
A backend with subagents runs the lenses in parallel. A backend without them runs the lenses in
sequence, in one context. Each lens returns candidate findings with their proof, never a verdict.
The main context verifies each proof, merges duplicates across lenses, groups by kind, ranks, and
writes. Never run build or test commands in more than one subagent at a time.

`spec-anchored-review.md` forbade splitting the judgement because the cap forced relative ranking.
Without a cap, and with severity defined by consequence, the lenses need not rank against each
other. The merge stays in one context, because only it sees duplicates across lenses.

## 11. Preconditions

`require_review_preconditions` checks:

1. Both artifacts present. Unchanged.
2. At least one `- [x]` item. Unchanged.
3. No `- [ ]` item. Unchanged.
4. **`.ralph/cycle-base` present.** New. Without it review cannot bound the cycle's work. The error
   names the file and states that build writes it.

The cited-spec gate is removed, and `have_cited_specs` with it. It existed because spec fidelity was
review's only real standard, and an empty anchor set left nothing to measure. A plan that cites only
rule files or the verification gate still ships code, and that code now gets reviewed. Ralph keeps
`cited_specs`, which the exit line counts.

`auto`'s phase 5 guard follows the change: it drops the `skipped — no cited specs` branch and gains
`skipped — no cycle base`.

## 12. One pass and the exit line

- **Iterations.** Review runs one pass. `hard_override` handling rejects `-n` on `review` with
  `Error: review runs one pass; -n does not apply.` The review branch of the iteration-cap `case`
  sets `max_iterations=1`.
- **Fingerprint.** `mode_converges_on_plan` keeps review, because the metrics `noop` flag reads the
  plan fingerprint for modes that never commit. With one pass the early exit never fires.
- **Exit line.** After the pass, Ralph prints a line it counts itself, whether or not the plan
  changed. This replaces the review branch of `convergence_message`:

```
Review filed 4 findings. Reviewed 3 specs and 14 changed files.
```

The findings count is the open items after the pass. The spec count is `cited_specs`. The file
count is the distinct changed paths from the base to `HEAD`, across every repository the base lists,
plus the tracked files of every repository created during the cycle. A clean review still prints
counts, so it stays distinguishable from a backend that did nothing, which is the reason the exit
line exists in `review-phase.md` §5.

The guard that stops a pass which reduces the shipped-item count stays.

## 13. Script changes

- **`write_cycle_base`** — writes `repo_state` to `.ralph/cycle-base` when absent. `cmd_loop`
  calls it in build mode before the first iteration, except on a dry run.
- **`cycle_changed_files`** — prints the distinct changed paths section 12 counts, reading
  `.ralph/cycle-base`.
- **`ARTIFACTS`** gains `.ralph/cycle-base`. `cmd_archive` moves it into `.ralph/<timestamp>/`.
- **`require_review_preconditions`** — drops the cited-spec check and adds the base check.
- **`have_cited_specs`** — removed.
- **`cmd_loop`** — rejects `-n` on review, sets review's cap to 1, and prints the section 12 exit
  line after review's pass.
- **`convergence_message`** — loses its review branch.
- **`cmd_auto`** — the phase 5 guard changes as section 11 states.
- **`usage()`** — the review mode line becomes "Review the cycle's work in one pass and file
  findings as new plan items", and the `-n` help drops review from "plan and review default: 6".

## 14. Prompt changes

- **`prompts/review.md`** is rewritten from scratch around sections 2 to 10. It keeps the workspace
  root and nested-repository paragraphs, the item schema and limits, the Simplified Technical
  English rules, and the ban on writing under `specs/`. It drops the finding budget, the convergence
  section, the editing rules for open items, the supersession rules, and "audit in one context".
- **`prompts/build.md`** gains the catalogue: all nine kinds, each with its test of proof, in exactly
  the words of `prompts/review.md`, as rules build meets before it commits. The "Document the why"
  line is replaced with:

```
- **Self-documenting code** — name things so the code needs no comment. Add a comment only for a
  why the code cannot carry, in one line. Put the reasoning in the commit message.
```

A reviewer that knows a rule and a builder that does not replenish violations as fast as review
drains them, so the two prompts carry the catalogue word for word.

- **`prompts/plan.md`** — unchanged, except that its review-finding `Spec` sentence names the four
  forms of section 8.
- **`templates/IMPLEMENTATION_PLAN.md`** — the `Spec` guidance names the four forms of section 8.

## 15. Documentation

- **`CLAUDE.md`** — the review paragraphs under "The implementation plan contract" and "Core loop
  flow" are rewritten for this model. The command table's review row drops "max 6 iterations, exits
  on convergence".
- **`AGENTS.md`** — the same edits as `CLAUDE.md`.
- **`README.md`** — the review row, the "at most ten open at a time" sentence, the convergence
  sentence for review, and the "At most 6 passes" cell.
- **`docs/plan-format.md`** — the three level definitions and the precondition sentence.
- **`CONTEXT.md`** — a lens is one group of standards, and a cycle ends when its artifacts are
  archived or cleaned.

## 16. Testing

In `test/review.bats` unless stated:

- Build writes `.ralph/cycle-base` in `repo_state` format when it is absent, and keeps an existing one.
- A dry-run build writes no base.
- `archive` moves `.ralph/cycle-base` into the timestamped directory. `clean` deletes it.
- Review exits 1 with the base error when `.ralph/cycle-base` is missing.
- Review runs on a plan whose items cite only the verification gate.
- `review -n 3` exits 1 with the one-pass error.
- Review runs exactly one backend invocation, whether or not the pass changes the plan.
- The exit line counts open items, cited specs and changed files, including a nested repository
  created after the base.
- `auto` skips review with `skipped — no cycle base` (`test/auto.bats`), and no longer reports
  `skipped — no cited specs`.
- The shipped-count guard still stops a pass that un-ticks an item.

Existing tests that assert the cited-spec gate, the review convergence line, or six review passes
are rewritten or removed.

## 17. Out of scope

- **archon-ralph.** Its port, its cycle loop and `ralph-review-cap.ts` follow in a separate spec.
- **Cycles in `auto`.** Repeating build and review until review files nothing needs a cost bound
  `auto` lacks. `auto` stays at one cycle.
- **Enforcing the catalogue in code.** Ralph counts and gates. It never checks a finding's kind,
  level or proof, which live in the prompt as today.
- **A commit field in `PROGRESS.md`.** The cycle base replaces the need.

## 18. Accepted risks

- **No second pass.** A defect the single pass misses stays unfiled until the next cycle. The lenses
  and the coverage line are the mitigation.
- **Argued `Critical`s.** A latent bug proven by argument can be wrong. It costs one build iteration.
- **Long reviews.** With no cap, a large cycle can file many findings, and the second build sizes to
  them. Grouping bounds `Major` and `Minor` items, and each finding has passed its test.
- **Manual flows that never archive.** The base persists, and each review re-reads a growing range.
  Archiving or cleaning ends the cycle.
