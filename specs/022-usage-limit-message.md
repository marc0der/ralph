---
id: "022"
created: 2026-11-15
area: [backend, output, auto]
related: ["003", "012", "018", "021"]
---

# Usage Limit Message

When the backend command exits non-zero, Ralph prints one message for every cause:

```
Error: backend command failed on iteration 5 (exit code 1)
```

An outage, a crash and a plan usage limit all look the same, and all exit 1. The operator must open
the raw stream to learn whether to wait an hour, wait a week, or debug.

This spec makes Ralph name a usage limit when the backend reports one, give its reset time, and exit
with a code of its own. Ralph does not wait or retry. Requested in
[marc0der/ralph#6](https://github.com/marc0der/ralph/issues/6).

## 1. Problem

On a Pro plan, a build that reaches the 5-hour limit ends like this:

```
====================== ITERATION 5 / 8 ====================
Error: backend command failed on iteration 5 (exit code 1)
```

The stream that Ralph saved for that iteration is expected to state the limit and its reset time
(see §6), but Ralph does not read it. A script that wraps `ralph` cannot tell a limit from a crash, because both exit 1.

## 2. Rule

- **Name the limit.** When the backend command exits non-zero and the iteration's stream shows that
  the backend refused work because of a usage limit, Ralph says so, names the limit when it can, and
  gives the reset time when the stream holds one.
- **Own exit code.** Such a run exits **75**. Every other backend failure keeps the backend's exit
  code.
- **No waiting.** Ralph never sleeps until the reset, and never retries the iteration. The operator
  re-runs.
- **No guessing.** When the stream holds no usage-limit signal that Ralph recognises, the output is
  the same as today.
- **Claude only.** This spec defines the signal for the `claude` backend. For `codex`, `copilot` and
  `pi`, the output is the same as today.

## 3. Behaviour

### Detection

The `claude` backend's stream carries `rate_limit_event` events. Each one has a `rate_limit_info`
object with a `status`, and often a `resetsAt` (Unix seconds) and a `rateLimitType`. A `status` of
`allowed` or `allowed_warning` means the request went ahead. Ralph reads the stream that the failing
iteration wrote. The iteration hit a usage limit when:

- the backend command exited non-zero; and
- the last `rate_limit_event` in the stream has a `status` that is a non-empty string other than
  `allowed` and `allowed_warning`.

Earlier events do not count. A warning event alone does not count: it appears in healthy runs.

Detection needs the stream on disk. A run that keeps no stream file, or whose file vanished, prints
today's message.

### Message

Ralph prints this in place of today's error line, before the hint:

```
Error: usage limit reached on iteration 5 (5-hour limit). It resets at 15:00.
```

- **Limit name.** `five_hour` prints `5-hour limit`. `seven_day` and any other `seven_day_*` type
  print `weekly limit`. For a missing or unknown type, Ralph leaves out the parenthesis.
- **Reset time.** Local time as `HH:MM` when the reset falls today. Otherwise the local date and
  time, `on YYYY-MM-DD at HH:MM`. With no `resetsAt`, the sentence reads `It resets later.` In a
  reset time that is already past, Ralph prints it as recorded.

The hint line follows, and changes to:

```
Hint: re-run 'ralph build' after the reset; the plan keeps its open items
```

The hint for each mode:

- `build` and `fix`: `Hint: re-run 'ralph <mode>' after the reset; the plan keeps its open items`
- `retro`: `Hint: re-run 'ralph retro' after the reset`
- `review`: `Hint: remove the findings this pass appended, then re-run 'ralph review' after the
  reset`, because review refuses a plan that holds open items.
- `plan`: `Hint: re-run 'ralph plan' with the same goal after the reset`, because Ralph does not
  echo the goal back.

The other output of a failed iteration is unchanged: the rendered stream or the raw dump, and the
`Raw stream:` pointer when the stream is kept.

### Exit code

The command exits 75 after the message. Every mode-specific step that runs on a backend failure
today still runs: plan's `finish_plan_run` and the retro's restore. As today, a failed iteration
writes no metrics record. When `finish_plan_run` itself fails, its exit 1 wins and its own error
prints after the usage-limit message.

### `auto`

`auto` treats exit 75 like any failed child: it records the phase and `child_exit=75` in
`.ralph/auto-state` and prints `Re-run: ralph auto --resume`. It then exits 75, not 1, so a
script that wraps `auto` can tell a limit from a crash. The phase report reads
`failed — usage limit` in place of `failed — exit 75`. The child's own message, with the reset time,
prints above the report. Under `auto`, the child prints no hint line: `auto`'s
`Re-run: ralph auto --resume` is the only re-run advice.

### `--dry-run`

No backend runs, so nothing changes.

## 4. Documentation

- `README.md` — a Troubleshooting entry: what the usage-limit message means, that Ralph does not wait,
  and to re-run after the reset, or `ralph auto --resume` under `auto`.
- `README.md` Reference — exit code 75 beside the other exit codes, or a new list of exit codes when
  none exists.
- `CLAUDE.md` — core loop flow step 7 names the usage-limit check on a failed iteration.

## 5. Testing

Each test uses a mock `claude` that writes a fixture stream and exits non-zero.

**Detection**
- A stream with a `rejected` event exits 75 and prints the usage-limit message.
- A stream with only `allowed_warning` events exits with the backend's code and prints today's
  message.
- A stream with a `rejected` event followed by an `allowed` event prints today's message.
- A successful backend exit with a `rejected` event in the stream is not a failure.
- With `--no-metrics`, a `rejected` stream still prints the usage-limit message.
- A `codex` mock that writes a `claude`-style `rejected` event prints today's message.

**Message**
- `five_hour` prints `5-hour limit`. `seven_day` and `seven_day_opus` print `weekly limit`. An
  unknown type prints no parenthesis.
- A reset later today prints `HH:MM`. A reset on another day prints the date. A missing `resetsAt`
  prints `It resets later.` The tests fix `TZ`.
- The hint names the failing mode, for each of `plan`, `build`, `fix`, `review` and `retro`.

**Side effects**
- A retro that hits the limit restores the learnings file.
- A plan that hits the limit still runs its end-of-run spec commit.

**auto**
- A child that exits 75 writes `child_exit=75`, the report reads `failed — usage limit`, and `auto`
  exits 75.

## 6. Accepted risks

- **The refusal shape is assumed.** Local streams hold only `allowed_warning` events. A refusal has
  not been captured yet, and the spec assumes it is a `rate_limit_event` with a status outside the
  two allowed values. If Claude reports a refusal some other way, Ralph prints today's message. That
  is no worse than now. A captured refusal stream should replace the test fixture.
- **The limit type names are assumed.** Only `overage` has been seen. An unseen name prints no
  parenthesis, so a wrong guess costs only the label.
- **Exit 75 can clash.** A backend that itself exits 75 for another reason is indistinguishable to a
  script that reads only the exit code. Ralph's message still tells the two apart. The `claude` CLI
  exits 1 on failure.
- **A limit hit mid-iteration can leave uncommitted work.** The re-run starts on that tree. This is
  the same as any failed iteration today.

## 7. Out of scope

- Waiting for the reset, or retrying the iteration.
- Usage-limit signals for `codex`, `copilot` and `pi`. A later spec can add each one.
- Other failure causes, such as outages, authentication errors or network errors.
- Warning the operator when utilisation passes a threshold.
