---
id: "022"
created: 2026-11-23
area: [build, review, retro]
related: ["021"]
---

# Progress Timestamps

`templates/PROGRESS.md` asks each entry for a `### [YYYY-MM-DD HH:mm]` heading, and the retro
prompt asks each learnings bullet for "today's date". No prompt says where the agent gets the time,
so the agent writes one that it guesses. This spec makes the build, review and retro prompts read
the dates and times they write into `PROGRESS.md` headings and learnings bullets from the clock.

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

The agent reads every date and every time it writes from `date`, run as the last command before
the edit that writes the heading or bullet, and copies the output exactly. The rule covers the heading of a new `PROGRESS.md`
entry and the date of a learnings bullet that gets today's date. It does not cover a date the
agent keeps unchanged, such as a kept bullet's date, or dates in code, tests and documents.

## 3. Behaviour

### `prompts/build.md`

Phase 4 (Finalise), step 2 (the `PROGRESS.md` entry) adds: run `date '+%Y-%m-%d %H:%M'` just
before you append the entry, and copy its output into the heading. The Phase 2 contradiction
record follows the same rule when it writes a heading. `fix` runs this prompt, so it gets the rule too.

### `prompts/review.md`

Phase 3 adds the same rule for the review entry heading.

### `prompts/retro.md`

"Use today's date for a new bullet" becomes: run `date +%F` once before you write the file, and
use its output for every bullet that gets today's date. That covers the new bullets and the
bullets this cycle observed again.

### `templates/PROGRESS.md`

The heading format does not change. A visible line after "Each entry must follow this
structure exactly:" reads: "Take the heading's time from `date '+%Y-%m-%d %H:%M'`. Its zone is
the sandbox's `TZ`, which is fixed when the sandbox is built and is UTC unless the host exported
`TZ`. On a run outside the sandbox it is the host's zone." The line holds no real-looking date.

### Timezone

`date` prints the local time of the machine that runs the backend. That is the sandbox's `TZ`
inside the container, and the host's zone on a run outside it, such as a warned `build` or
`auto --force`. `container/devcontainer.json` passes
`"TZ": "${localEnv:TZ:UTC}"` as an image build argument, and the Dockerfile fixes it with
`ENV TZ`. The sandbox keeps the `TZ` the host exported when its image was built, or UTC if it
exported none. Ralph does not change this. The template line names the timezone source, so
an operator who wants local time exports `TZ` on the host and runs `ralph sandbox --rebuild`.

## 4. Documentation

- `templates/PROGRESS.md` as in §3.
- `docs/sandbox.md`: the sandbox keeps the `TZ` the host exported when its image was built, or
  UTC if it exported none; export `TZ` and run `ralph sandbox --rebuild` to change it.
- `CLAUDE.md` needs no change.

## 5. Testing

Prompt rules have no runtime check, so the tests read the prompt files:

- `prompts/build.md` and `prompts/review.md` each contain `date '+%Y-%m-%d %H:%M'`.
- `prompts/retro.md` contains `date +%F`, and no longer contains `Use today's date`.
- `templates/PROGRESS.md` still contains `### [YYYY-MM-DD HH:mm]`. It also contains
  `date '+%Y-%m-%d %H:%M'` and `TZ`, and the whole file still fails `have_progress_entries`.

## 6. Accepted risks

- An agent can still ignore the rule. The rule makes the right action one tool call. Nothing
  detects a heading the agent made up, because §7 leaves the wall-time check out of scope.
- An entry written late in a long iteration records the time it was written, not the time the
  item began. The heading marks when the record was made, which is what the log is for.
- A host without `TZ` gets UTC headings. A cycle whose passes run both inside and outside the
  sandbox mixes zones in one `PROGRESS.md`, and the heading does not show which zone it uses.

## 7. Out of scope

- Ralph writing the timestamp itself, for example through a `{{NOW}}` placeholder.
- Checking the headings against the run's wall time.
- Changing the heading format.
- Dates the planner writes, such as a new spec's `created` field.
