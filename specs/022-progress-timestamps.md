---
id: "022"
created: 2026-11-23
area: [build, review, retro]
related: ["021"]
---

# Progress Timestamps

`templates/PROGRESS.md` asks each entry for a `### [YYYY-MM-DD HH:mm]` heading, and the retro
prompt asks each learnings bullet for "today's date". No prompt says where the agent gets the time,
so the agent writes one that it guesses. This spec makes every prompt that writes a date or a time
read it from the clock.

## 1. Problem

A build of 9 items ended at 09:35. Its `PROGRESS.md` entries ran from 09:45 to 13:15. The builder
had no clock reading, so it made up a plausible time for each entry. The retro pass of the same
lifecycle dates its bullets the same way: `prompts/retro.md` says "Use today's date for a new
bullet" and gives no source for it.

A wrong time does not fail any check. `require_progress_entries` reads only the
`### [YYYY-MM-DD` prefix. But it misleads the operator, who reads the log to learn when each item
shipped, and a wrong date in a learnings bullet changes which bullet retro drops first at the
30-bullet limit.

## 2. Rule

The agent reads every date and every time it writes from `date`, run in the same turn just before
it writes, and copies the output exactly. It never writes a date or a time from memory, from the
prompt, or from an earlier entry.

## 3. Behaviour

### `prompts/build.md`

Phase 3, step 2 (the `PROGRESS.md` entry) adds: run `date '+%Y-%m-%d %H:%M'` just before you
append the entry, and copy its output into the heading. The Phase 2 contradiction record follows
the same rule when it writes a heading. `fix` runs this prompt, so it gets the rule too.

### `prompts/review.md`

Phase 3 adds the same rule for the review entry heading.

### `prompts/retro.md`

"Use today's date for a new bullet" becomes: run `date +%F` once before you write the file, and
use its output for every bullet that gets today's date. That covers the new bullets and the
bullets this cycle observed again.

### `templates/PROGRESS.md`

The heading format does not change. The template's comment above the format states that the
heading's time comes from `date '+%Y-%m-%d %H:%M'`.

### Timezone

`date` prints the container's local time. `container/devcontainer.json` sets
`"TZ": "${localEnv:TZ:UTC}"`, so the container follows the host's `TZ` when the host exports
one and uses UTC otherwise. Ralph does not change this. The template comment names the
timezone source, so an operator who wants local time exports `TZ` on the host.

## 4. Documentation

- `templates/PROGRESS.md` as in §3.
- `CLAUDE.md` needs no change.

## 5. Testing

Prompt rules have no runtime check, so the tests read the prompt files:

- `prompts/build.md` and `prompts/review.md` each contain `date '+%Y-%m-%d %H:%M'`.
- `prompts/retro.md` contains `date +%F`, and no longer contains `Use today's date`.
- `templates/PROGRESS.md` still contains `### [YYYY-MM-DD HH:mm]`, and its exemplar heading still
  fails `have_progress_entries`.

## 6. Accepted risks

- An agent can still ignore the rule. The rule makes the right action one tool call, and review
  can see a heading that falls outside the run's wall time.
- An entry written late in a long iteration records the time it was written, not the time the
  item began. The heading marks when the record was made, which is what the log is for.
- A host without `TZ` gets UTC headings. That is consistent, and §3 says how to change it.

## 7. Out of scope

- Ralph writing the timestamp itself, for example through a `{{NOW}}` placeholder.
- Checking the headings against the run's wall time.
- Changing the heading format.
