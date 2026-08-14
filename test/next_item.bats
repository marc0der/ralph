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
