---
id: "030"
created: 2026-11-25
area: [retro]
amends: ["021", "022"]
---

# Ranked Learnings

Today the retro keeps up to 30 learnings under four headings, and removes the bullets with the
oldest dates when the file is full. The file fills, and the retro then drops a learning because of
its age, not because of its value. This spec makes the learnings file a short list of at most 10
learnings, ranked by importance. The retro removes the least important learning, never the oldest.

This spec amends `021-retro-phase.md`. It replaces the last bullet of §2, §3 Format, §3 Rewrite
rules, §4 Summary, the promotion clauses of §5, the format and summary tests of §10, and the first
two risks of §11. The rest of 021 stands. It also replaces the `prompts/retro.md` clauses of
`022-progress-timestamps.md` §2, §3 and §5: the retro prompt no longer runs `date +%F`, and the test
that requires it goes.

## 1. Problem

The learnings file of this repository on 2026-11-25 shows the problem:

- **The file is full.** It holds 30 bullets, the cap of 021 §3: 4 Environment, 15 Tooling and 11
  Codebase.
- **The retro drops by age.** The retro of the `feat/claude-phase-defaults` cycle added 3 bullets.
  To stay at 30, it dropped 3 of the 8 bullets dated 2026-11-15, the oldest date: the 3 nearest
  the end of the file. It did not compare their value with the value of the bullets it kept.
- **Most bullets are narrow.** Many bullets record one trick for one test, such as a ShellCheck
  code or a BATS quirk. A reader cannot find the few learnings that matter among them.
- **The promotion section is empty.** No learning has moved to the guardrails file since 021
  shipped.

## 2. Rule

- **A short list.** The learnings file holds at most 10 learnings.
- **Ranked by importance.** The file holds one list. The first bullet is the most important. The
  file order is the rank.
- **Cost times likelihood.** The retro ranks a learning by what a future cycle loses without it,
  and by how likely the next cycle is to need it. A learning that this cycle needed again moves
  up. Age does not change the rank.
- **The least important learning leaves.** When more than 10 learnings remain after the
  removals, the retro ranks them all together, and the lowest leave. The retro keeps no record
  of a learning that leaves.
- **No promotion section.** The retro still never edits a guardrails file. It no longer proposes
  promotions, and Ralph prints no promotion banner.

## 3. The learnings file

### Format

```
# Learnings

- `npm ci` fails behind the proxy here. Set `NODE_EXTRA_CA_CERTS=/etc/ssl/proxy.pem` first.
- JDK 11 is not installed. Run Gradle through `nix-shell -p jdk11 --run './gradlew test'`.
```

- The first line is `# Learnings`.
- Each learning is one bullet on one physical line: `- <text>`. A bullet carries no date.
- The text holds at most 40 words, where a word is a maximal run of non-whitespace characters.
- The file holds at most 10 bullets.
- The file holds nothing else: no other headings and no prose. Blank lines are allowed.
- A file that holds only `# Learnings` is valid.

### Admission test

The three tests of 021 §3 stand. A candidate that passes them still leaves when it ranks below
the 10th place. For test 2, a commit message does not count.

### Rewrite rules

Each retro writes the whole file again:

- It reads the current learnings as candidates, together with the cycle's candidates.
- Admission tests 1 and 3 apply to the cycle's new candidates only. A current learning leaves
  through the removal rules or the rank.
- It merges a candidate into an existing learning that says the same thing, and does not
  duplicate it.
- It removes a learning that this cycle contradicts, for example when JDK 11 is now installed.
- It removes a learning that `AGENTS.md`, `CLAUDE.md`, a spec or a code comment now states.
  A commit message does not count, because plan and build never read `git log`.
- Text in an example block of a spec or a prompt does not state a learning.
- It ranks every remaining learning by cost times likelihood, and writes the first 10 in rank
  order.

### A file in the old format

A learnings file in the format of 021 §3 is not converted. Plan, build and review read it as
advice, as today, until the next retro. The next retro ignores it and starts over: it writes a new
file from the cycle's candidates only. `.ralph/learnings.prev.md` keeps the old file, as after any
successful pass.

## 4. `ralph retro`

### Summary

After a successful pass, Ralph compares the bullets of the old and new files by their text. A
bullet only in the new file is **added**. A bullet only in the old file is **dropped**. A reworded bullet counts as one dropped and one
added. Ralph prints to stderr:

```
Retro kept 10 learnings: 3 added, 2 dropped.
```

The kept count is every bullet in the new file. Ralph prints no promotion banner.

### Iteration card

The retro iteration card counts the learnings on file before the pass, in either format.

### A local retro prompt

When the format check fails and the prompt came from `PROMPT_retro.md`, Ralph also prints
`This project has its own PROMPT_retro.md; delete it and run 'ralph init --prompts' to get the ranked-learnings prompt.`

## 5. The retro prompt

`prompts/retro.md` instructs the backend to apply the admission test, the rewrite rules and the
format of §3 of this spec, and to ignore a learnings file in the old format. It no longer names a
promotion section or a promotion rule. Admission test 2 still searches the guardrails files, the
specs and the code comments.

## 6. Documentation

- `README.md`: "Keeping learnings" states the cap of 10, the ranked list and the removal of the
  least important learning. The banner bullet goes.
- `CLAUDE.md` and `AGENTS.md`: the retro paragraph states the new summary line, and no longer names
  the promotion banner.

## 7. Testing

**Format**
- A pass that writes an 11th bullet, a `##` heading or a 41-word bullet fails. The error names the
  line.
- A pass that writes only `# Learnings` succeeds.
- A pass that writes 10 bullets succeeds.

**Summary**
- The counts of added and dropped bullets match a known pair of files in the new format.
- A pass over an old-format file counts every old bullet as dropped.
- The summary line names no refreshed count.
- A pass prints no promotion banner, even when the old file held a `Promote to AGENTS.md` bullet.

**Iteration card**
- The card counts the bullets of an old-format file and of a new-format file.

**Local prompt**
- A 021-era `PROMPT_retro.md` whose pass fails the format check prints that line.

**Prompt**
- `prompts/retro.md` names the cap of 10 and the ranking, and no longer names `Promote to
  AGENTS.md`.

## 8. Accepted risks

- **The rank is a judgement.** Ralph checks the format, not the order. A retro can rank a learning
  too low and drop it. The backup keeps one step of undo, and a learning that a later cycle needs
  again comes back.
- **A wrong learning can rank high.** It is advice, and guardrails win. The next retro removes a
  learning that the cycle contradicts. A wrong learning that no cycle contradicts stays until a
  stronger candidate outranks it or the operator deletes it.
- **The retro can reword a learning.** The summary then counts one dropped and one added.
- **Durable facts stay in the list.** Without a promotion section, a fact that belongs in the
  guardrails file takes one of the 10 places until the operator moves it there by hand.

## 9. Out of scope

- A configurable cap.
- A record of dropped learnings beyond `.ralph/learnings.prev.md`.
- Ralph checking the rank order.
