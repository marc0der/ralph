#!/usr/bin/env bats

load test_helper

# The iteration-start announcement: build mode prints the first incomplete
# plan item under the iteration banner, so a running loop shows what it is
# attempting instead of staying silent until the backend finishes.

@test "build announces the first incomplete plan item at iteration start" {
    "$RALPH" init
    printf -- '- [x] **A1. Shipped thing**\n- [ ] **B2. Next thing to build**\n- [ ] **C3. Later thing**\n' > IMPLEMENTATION_PLAN.md

    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Next:    B2. Next thing to build"* ]]
}

@test "announcement strips markdown emphasis from the item title" {
    "$RALPH" init
    printf -- '- [ ] **Bold title**\n' > IMPLEMENTATION_PLAN.md

    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Next:    Bold title"* ]]
    [[ "$output" != *"Next:    \*\*"* ]]
}

# Index entries carry a trailing link to the item's task file. That is noise in
# a one-line announcement, so it is stripped along with the emphasis markers.
@test "announcement strips the trailing link to the task file" {
    "$RALPH" init
    printf -- '- [ ] **Add PATCH endpoint** — accept partial updates. → [002-patch.md](plan/002-patch.md)\n' > IMPLEMENTATION_PLAN.md

    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Next:    Add PATCH endpoint — accept partial updates."* ]]
    [[ "$output" != *"plan/002-patch.md"* ]]
}

@test "announcement strips a bare task-file link with no arrow" {
    "$RALPH" init
    printf -- '- [ ] **Wire up auth** [003-auth.md](plan/003-auth.md)\n' > IMPLEMENTATION_PLAN.md

    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Next:    Wire up auth"* ]]
    [[ "$output" != *"003-auth.md"* ]]
}

@test "only the first incomplete item is announced" {
    "$RALPH" init
    printf -- '- [ ] **First open**\n- [ ] **Second open**\n' > IMPLEMENTATION_PLAN.md

    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Next:    First open"* ]]
    [[ "$output" != *"Next:    Second open"* ]]
}

@test "a long item title is truncated to the line width" {
    "$RALPH" init
    local long_title
    long_title=$(printf 'X%.0s' $(seq 1 150))
    printf -- '- [ ] %s\n' "$long_title" > IMPLEMENTATION_PLAN.md

    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Next:    XXX"* ]]
    [[ "$output" == *"..."* ]]
    [[ "$output" != *"$long_title"* ]]
}

@test "no announcement when every plan item is complete" {
    "$RALPH" init
    printf -- '- [x] **A1. Shipped**\n' > IMPLEMENTATION_PLAN.md

    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"Next:"* ]]
}

@test "plan mode does not announce a next item" {
    "$RALPH" init
    printf -- '- [ ] **B2. Open item**\n' > IMPLEMENTATION_PLAN.md

    run "$RALPH" plan --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"Next:"* ]]
}

# Regression: the item lookup ends in a `sed ... q` that closes the pipe at the
# first match, so on a plan larger than the pipe buffer the producer feeding it
# dies of SIGPIPE. Under `set -o pipefail` that made the pipeline non-zero, and
# the guarded assignment discarded the item it had just read successfully.
# Keep the plan above 64KiB and under the '## Items' heading, or the failure
# goes back to being a race the test only loses one run in ten.
@test "a long plan announces its first item without aborting the loop" {
    "$RALPH" init
    {
        printf -- '## Items\n\n- [ ] **First open item**\n'
        for i in $(seq 1 4000); do
            printf -- '- [ ] **Filler item %s**\n' "$i"
        done
    } > IMPLEMENTATION_PLAN.md
    [[ "$(wc -c < IMPLEMENTATION_PLAN.md)" -gt 65536 ]]

    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Next:    First open item"* ]]
    [[ "$output" == *"Completed 1 iterations."* ]]
}
