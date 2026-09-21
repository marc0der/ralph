# Spec-Anchored Review

Corrective follow-up to `specs/review-phase.md`. That spec anchored the review phase on
`IMPLEMENTATION_PLAN.md`: review asked only whether `build` did what each `- [x]` item said. This
spec moves the anchor to `specs/`, and replaces sections 1 to 5 of `review-phase.md`.

## 1. Problem

Ralph converges twice and drifts anyway.

`plan` loops over `specs/` until a pass changes no file. `build` implements each item and ticks it.
`review` confirms each item was implemented. Every hop reports convergence, and the code still does
not do what the specification says.

The reason is that each hop loses a little and no hop measures the whole distance. `plan`
decomposes prose into items capped at 150 words and 8 steps, and detail falls out in the
compression. `build` executes the item literally and never re-reads the clause behind it. `review`
then measures the second hop only. A run in which every item is implemented perfectly still lands
short of the specification by whatever `plan` failed to carry across, and nothing in the loop can
see that gap, because the only artifact that records it — the specification — is the one artifact
review is forbidden to read.

An ad-hoc adversarial pass comparing `specs/` against the tree finds those gaps immediately. The
loop cannot, by construction.

## 2. Model

**Review audits spec fidelity.**

`plan` reads `specs/` and produces items. `build` implements them. `review` reads the specifications
this cycle worked from and asks whether the tree satisfies them. Findings become `- [ ]` items, as
before. `build` drains them, as before.

### What `review-phase.md` §1 got right

That section rejected spec anchoring for a specific, documented failure. A reviewer that may fault
the plan "has no fixed standard to measure against — it can always find the work wanting by
proposing an item the planner did not write." The run that motivated it audited a three-item plan,
confirmed all three items correct, and then reported the feature as unimplemented because the plan
had never scoped the rest.

That objection is sound and this spec does not dismiss it. It conflates two powers that must now be
separated:

- **Coverage.** "Clause §4.2 requires X. The tree has no X." This is a fact about the tree. It is
  falsifiable, and an implementation of X closes it permanently.
- **Decomposition.** "I would have split this item differently, scoped it wider, or ordered it
  otherwise." This is unfalsifiable and unbounded, and it is what made the plan a moving target.

Review gains the first power and is denied the second. The ban in §1 on judging the plan's
decomposition survives verbatim; only the ban on judging its coverage lifts.

The other guards `review-phase.md` §1 relied on are replaced rather than removed. Section 4 bounds
which code a defect finding may examine. Section 4 also bounds nits to written rules. Section 3
bounds which specifications are in force. Each of these is a fixed standard, and together they do
the work that "never read `specs/`" used to do on its own.

### The plan is no longer the requirement

Item fidelity is gone. No severity level in section 4 corresponds to "build did not implement what
the item names". The question is instrumental: an item followed to the letter that leaves the clause
unmet is a finding, and an item deviated from that satisfies the clause is not. Review measures the
distance that matters and stops measuring the one that does not.

`- [x]` markers remain immutable, now trivially: review does not judge items at all.

## 3. The anchor set

Review audits **the specifications this cycle worked from**, not the whole `specs/` corpus.

`specs/` is a chronological record, not a statement of current requirements. In this repository
`multi-backend.md` says Ralph supports Claude only, `copilot-backend.md` says it supports three
backends, and `pi-backend.md` says four. All three were true when written. A reviewer that reads the
corpus and takes each file literally files Critical drift against correct code.

The anchor set is therefore derived from the plan:

> The anchor set is the set of distinct `specs/…` paths that appear in a `Spec:` field of
> `IMPLEMENTATION_PLAN.md`.

This is machine-derivable, it needs no new artifact and no status header on any spec, and it
includes any specification `plan` authored mid-cycle, because `plan` cites what it authors.

Two citations are excluded. The terminal verification item cites `AGENTS.md verification gate` or
`CLAUDE.md verification gate` and names no specification. A Minor finding cites a path under the
rules directory (section 4) and names no specification either. Neither enters the anchor set.

Deriving the *set* from the plan does not re-anchor the *judgement*. The plan says which documents
are in force. The specification decides whether the code is right. Each spec in the set is audited
**whole**, so a clause `plan` read and never decomposed into an item is in range — which is the
drift this spec exists to catch.

### Accepted gap

A specification that `plan` read and produced no item from is invisible to review. Citations cannot
see it. This is the one drift case the design does not catch, and it is accepted: closing it needs
either a goal passed to review or a recorded cycle start point, both of which are out of scope
(section 14).

## 4. Checks and severity

Findings carry one of three levels.

| Level | Definition | `Spec:` cites | Code in range |
|-------|------------|---------------|---------------|
| **Critical** | The tree does not satisfy a clause of a spec in the anchor set. | `specs/file.md` plus item number or section name | the whole tree |
| **Major** | The code this cycle committed is defective: a bug, an unhandled error, an unhandled edge case, or a quality problem. | `IMPLEMENTATION_PLAN.md` item "<title>" | the cycle's commits |
| **Minor** | The code this cycle committed violates a written rule. | the rule file plus the rule name | the cycle's commits |

Every level carries the same burden of proof: name a behaviour or a rule, and show the tree does not
have it. A lower level is a different target, never a weaker standard of evidence.

Where two levels fit, the higher one wins. Two passes over the same state must agree on the level; a
pass that relabels a finding changes the plan and stops the loop converging.

### Critical: drift from the spec

A Critical names a clause of a spec in the anchor set and proves the tree does not satisfy it. It
does not matter which item was supposed to deliver it, or whether any item did.

A clause the specification itself marks out of scope is not a finding. Most specs in this repository
carry an explicit out-of-scope section, and it binds review exactly as it binds `plan`.

A document is in range when a cited spec prescribes its content. `review-phase.md` §12 prescribes
what `CLAUDE.md`, `AGENTS.md` and `README.md` must say, and under the plan anchor that became
unfileable. Under the spec anchor it is fileable again and it is Critical, because a prescribed
deliverable is missing like any other. Wording no cited clause prescribes remains unfileable.

### Major: defective code

A Major is a defect in code this cycle committed. It has no clause behind it — a null dereference
breaches no specification — so it cites the plan item whose commits shipped it.

The range is the cycle's commits, not the tree and not the `Files` of any item. `prompts/build.md`
Phase 3 requires `build` to fix an unrelated red suite and explicitly overrides the item's `Scope`
to do it, so code outside every `Scope` ships under this cycle and is audited with it. The commits
are found from the `PROGRESS.md` entries `build` appends per shipped item, and from `git log` in the
repository that owns the paths in hand.

The bound is what makes Major exhaust. An unbounded defect sweep re-audits code no cycle touched, on
every pass, forever.

**A failing test suite produces at most one Major for the whole run.** File it once and name the
failing tests. Its `Spec:` field is `IMPLEMENTATION_PLAN.md` with the words `whole plan` in place of
a title. This is the one finding that belongs to no item.

### Minor: violations of a written rule

`review-phase.md` §3 ends "There is no third level", and §14 lists as out of scope "any severity
tier resting on `CLAUDE.md` or `AGENTS.md`". This spec readmits the tier under a constraint that
answers the original objection.

> A Minor must name the written rule it violates. A preference with no written source is not
> fileable at any level.

Rules live in a rules directory whose location is stated in the project's `AGENTS.md` or
`CLAUDE.md`. The directory is not at a fixed path and is not named by Ralph. A project with no rules
directory can produce no Minor finding at all; that is a floor, not an invitation to fall back on
taste.

The constraint buys the two properties the loop depends on. Decidability: the rule is text, so two
passes over the same state reach the same verdict, which a naming preference never guarantees.
Exhaustibility: a finite rule set over the cycle's commits is a finite supply, and each fix is
permanent, so the queue drains instead of regenerating.

Exhaustibility also requires that `build` stop producing the violations. Section 10 therefore points
all three prompts at the rules directory, not review alone. A reviewer that knows the rules and a
builder that does not replenishes the supply exactly as fast as it drains.

In a meta repository the rules directory is resolved per repository, from the `AGENTS.md` or
`CLAUDE.md` of the repository that owns the path in hand, exactly as `prompts/review.md` already
resolves operational guardrails.

## 5. Authority over the plan

Review's power over `IMPLEMENTATION_PLAN.md` is **additive**.

- It appends items for unmet clauses, defects and rule violations.
- It never re-decomposes, re-scopes or re-orders an item written by `plan`.
- It never alters a `- [x]` marker.
- "I would have planned this differently" is not a finding at any level.

Section 7 guarantees that a review run starts with no open items, so every open item review meets on
pass 2 or later is its own finding from an earlier pass. The seven editing rules inherited from
`prompts/plan.md` — refine, insert, reorder, never move a closed item, never delete, resolve every
`[~]` — therefore only ever act on review's own output, and they carry over unchanged. Review's own
three additional rules in `review-phase.md` §4 also carry over unchanged.

The severity prefix in the title keeps review's items distinguishable from the planner's by grep, as
`review-phase.md` §3 intended.

## 6. Finding budget

`IMPLEMENTATION_PLAN.md` holds at most **10 open findings** at one time.

The cap rises from 5 because the anchor widened. Review no longer audits shipped items; it audits
whole specifications, including clauses no item covered, so the first pass of a multi-spec cycle
legitimately finds more. The cap remains a standing invariant on the file rather than a per-pass
quota, for the reason `review-phase.md` §3 gives: stated per pass it bounds nothing across a six-pass
run.

A pass counts the `- [ ]` items before it writes anything and files at most the difference. A pass
that finds the plan already at 10 files nothing and changes nothing, and the loop converges on it.

Rank every finding against every other before choosing. Critical outranks Major, which outranks
Minor. File the worst. Drop the rest, and name a dropped finding in the final message if it is worth
naming, never in the plan.

Strict ranking means a Minor is filed only when fewer than ten Critical and Major findings exist.
That is intended: nits get attention when nothing worse is outstanding, and never instead of
something worse.

`calculate_build_iterations` sizes the following build at `ceil(open × 1.2)`, so a full queue of ten
gives the trailing build of `ralph auto` twelve iterations to drain it.

## 7. Preconditions

Review keeps the three preconditions in `review-phase.md` §7 and adds a fourth:

1. Both artifacts present — `IMPLEMENTATION_PLAN.md` and `PROGRESS.md`.
2. At least one `- [x]` item. With none, this cycle shipped nothing.
3. No `- [ ]` items. Review audits finished work, and this is what makes pass 1's empty-queue state
   true by construction (section 5).
4. **At least one `specs/` path cited in a `Spec:` field.** With none, the anchor set is empty and
   review has nothing to audit.

The fourth gate is new and is the one the other three do not cover: a plan whose items all cite the
verification gate satisfies gates 1 to 3 and still gives review no specification to read. Without
the gate that run produces an immediate convergence with a count of zero, which `review-phase.md` §5
specifically requires be distinguishable from a backend that did nothing.

All four run unconditionally beside `require_init_artifacts`, so `-n` cannot bypass them. Items
marked `[~]` neither anchor nor block a run.

The error for gate 2 continues to name `.ralph/<timestamp>/`. The plan supplies the citations and is
gitignored, so `review-phase.md` §7's destructible-anchor argument holds unchanged: archive or clean
a cycle before reviewing it and that cycle is unreviewable.

## 8. Convergence and the exit line

Convergence is unchanged: a pass that leaves `IMPLEMENTATION_PLAN.md` unchanged has found nothing
new, and the loop exits on it. `-n` caps a run but never disables the exit.

`plan_state_hash` is unchanged and still fingerprints `IMPLEMENTATION_PLAN.md` plus `specs/`. Review
now **reads** `specs/` and still never writes it, so the `specs/` term stays inert for review. The
ban on writing is load-bearing twice over: a reviewer that may amend a specification manufactures
its own standard, and a write to `specs/` changes the hash and defeats the exit.

The exit line must keep asserting scope, and must keep being counted by Ralph rather than claimed by
the agent, for the reason `review-phase.md` §5 gives: a clean review produces no commit, no file
change and a metrics line of zeros, which is otherwise indistinguishable from silent failure. The
count changes from shipped items to cited specs, because that is now what the pass swept:

```
Review converged — pass 2 found nothing new. Audited 3 specs.
```

The per-pass coverage statement in the agent's final message changes with it:

```
Audited N of M specs.
```

`M` is the size of the anchor set. `N` is the number the pass read. The two must match.

## 9. Script changes

Ralph enforces none of the severity rules or the finding budget; those live in the prompt, as they
do today. Four changes:

- **`cited_specs`** — a new helper beside `count_plan_items`. It reads `plan_items_body`, keeps
  lines whose first field is `Spec:`, extracts every `specs/…` path, and prints the distinct paths
  sorted with `LC_ALL=C`. Reading `plan_items_body` rather than the whole file means the exemplar
  under `## Entry Format` is excluded exactly as it is for marker counts. A path is the whole
  non-space, non-backtick token that contains `specs/`, so a nested repository's
  `source/svc/specs/x.md` stays distinct from the root's `specs/x.md`.
- **`have_cited_specs`** — a predicate beside `have_open_items` and `have_shipped_items`, true when
  `cited_specs` prints at least one line.
- **`require_review_preconditions`** — a fourth check calling `have_cited_specs`, with a message
  naming the cause and pointing at `ralph plan`.
- **`convergence_message`** — review's branch counts `cited_specs` instead of `^- \[x\]`, and its
  wording changes from "Audited N shipped items" to "Audited N specs". The plan branch is untouched.

`usage()` carries one stale sentence: the Modes list reads "review — Audit shipped items against
the plan, file findings as new plan items". It becomes "Audit the cycle's specs against the code,
file findings as new plan items". No other usage string changes.

No change to `cmd_loop`, the mode dispatch, `mode_converges_on_plan`, `plan_state_hash`, the push
block, the metrics schema, or the goal handling. Review continues to refuse `-g`.

The existing guard that fails a review pass which reduces the shipped-item count stays. Review has
even less reason to touch a `- [x]` marker now, and the guard costs nothing.

One change outside `cmd_loop` follows from `specs/auto-lifecycle.md` §2, which forbids `auto`'s guards
drifting from the hard stops: the phase 5 guard in `cmd_auto` also calls `have_cited_specs`, and skips
review with the reason `no cited specs` when it is false. Without it `auto` starts a review its guard
believed legal, the child exits 1 on the fourth gate, and the lifecycle is reported as failed for a
condition `auto` exists to absorb. The mock planner in the tests cites a spec on the item it appends,
so a lifecycle test still reaches phase 5.

## 10. Prompt changes

- **`prompts/review.md`** — rewritten to sections 2 to 8. The ban "Never read, create or edit
  anything under `specs/`" becomes read-only access to the anchor set; the ban on writing stays
  absolute and keeps its reasoning.
- **`prompts/plan.md`**, **`prompts/build.md`**, **`prompts/review.md`** — the "Operational
  guardrails" bullet in Phase 1 gains a clause telling the agent to follow the pointer in `AGENTS.md`
  or `CLAUDE.md` to the project's rules directory and read it. The pointer is already in front of all
  three; none of them follows it today.
- **`prompts/build.md`** — the sentence "A review finding points at the plan item it audits instead,
  so it has no spec clause to contradict" is false under section 4: a Critical cites a spec clause.
  It is revised so the `[~]` route for a contradicted item applies to a Critical as to any item.
- **`prompts/plan.md`** — the `Spec` field description gains the three review forms from section 4.
  The existing sentence covering the single review form is replaced.
- **`templates/IMPLEMENTATION_PLAN.md`** — the `Spec` rule line gains the same three forms.

## 11. Documentation

`README.md` keeps its shape. Two edits:

- The `review` row in `## Commands` changes from auditing shipped items to auditing the cycle's
  specs. It keeps its density and gains no new column.
- The sentence ordering `review` before `archive` and `clean` keeps its advice and changes its
  reason: the plan is the only record of which specs the cycle worked from, so a closed-out cycle
  can no longer be audited.

The options table, the metrics paragraph, the prompt-resolution list and the goal paragraph are
unchanged. Review still refuses `-g`.

`CLAUDE.md` and `AGENTS.md` carry the detail, in the section that currently states "Review audits
build fidelity only". It is replaced by: the anchor set and how it is derived, the three severity
levels and what each cites, the code range for Major and Minor, the written-rule requirement for
Minor, the additive-only authority over the plan, the budget of 10, and the fourth precondition.

## 12. Testing

All tests use `--dry-run` or mock backends.

- `cited_specs` returns distinct paths from `Spec:` fields and ignores paths in `Files:`.
- `cited_specs` excludes `AGENTS.md verification gate` and `CLAUDE.md verification gate` citations.
- `cited_specs` excludes a rules-directory citation.
- `cited_specs` ignores the exemplar under `## Entry Format`.
- `cited_specs` deduplicates two items citing the same spec.
- Review exits non-zero when the plan cites no spec, and the message names the cause.
- The citation gate still fails when `-n` is passed.
- The citation gate does not fire when at least one item cites a spec.
- A plan with no `## Items` heading still derives citations, covering `plan_items_body`'s whole-file
  fallback.
- The convergence message reports the cited-spec count, not the shipped-item count.
- The convergence message reports a count of 1 for a plan whose items all cite one spec.
- Every existing test in `test/review.bats` that seeds a plan now seeds a `Spec:` citation and still
  passes.
- `--help` shows the revised review line in the Modes list.
- Existing plan and build tests continue to pass.

## 13. Out of scope

- A goal for `review`. `-g` stays refused, and `auto` forwards it to `plan` alone.
- A recorded cycle start point or a plan-path argument for `ralph review`.
- Status or supersession headers on spec files, and any notion of a retired spec.
- Ralph enforcing the finding budget or the severity levels; both stay in the prompt.
- Review writing `specs/`, or writing any file other than `IMPLEMENTATION_PLAN.md` and a `PROGRESS.md`
  supersession entry.
- Review re-decomposing, re-scoping or re-ordering an item `plan` wrote.
- Hardening `Done when` criteria (`review-phase.md` §15). It matters less once review measures
  against the spec, and it remains a separate change.
- Commits, pushes and pull request comments.

## 14. Accepted risks

- **The silent-drop gap.** A spec `plan` read and produced no item from is outside the anchor set
  (section 3).
- **Minor is rare.** Strict ranking at a cap of 10 files a nit only on a cycle with fewer than ten
  substantive findings (section 6).
- **Dogfooding is one cycle behind.** `resolve_prompt` reads the project's `PROMPT_review.md`, then
  `$CONFIG_DIR/prompts/review.md`. It never reads this repository's `prompts/review.md`. A build
  iteration that rewrites `prompts/review.md` does not change the review pass that follows it in the
  same `ralph auto` run unless `install.sh` has run in between, so the cycle that implements this
  spec is audited by the old reviewer.
