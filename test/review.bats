#!/usr/bin/env bats

load test_helper

@test "review runs against a plan of shipped items" {
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n' >> IMPLEMENTATION_PLAN.md
    run "$RALPH" review --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[dry-run] Would run: claude -p"* ]]
}

@test "review fails without init artifacts" {
    run "$RALPH" review
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"missing workspace artifacts required for 'review'"* ]]
    [[ "$output" == *"IMPLEMENTATION_PLAN.md"* ]]
    [[ "$output" == *"PROGRESS.md"* ]]
    [[ "$output" == *"Run 'ralph init'"* ]]
}

@test "review fails when only IMPLEMENTATION_PLAN.md is present" {
    # Review reads PROGRESS.md as a claim to verify and writes supersession
    # entries back to it, so the second artifact is a real requirement.
    echo "- [x] **Shipped task**" > IMPLEMENTATION_PLAN.md
    run "$RALPH" review
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"missing workspace artifacts required for 'review'"* ]]
    [[ "$output" == *"PROGRESS.md"* ]]
}

@test "review fails with no shipped items" {
    echo "- [ ] **Open task**" > IMPLEMENTATION_PLAN.md
    touch PROGRESS.md
    run "$RALPH" review
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"no shipped items"* ]]
}

@test "review names .ralph when the plan holds no shipped items" {
    # The anchor set is gitignored and destructible: 'ralph archive' moves the
    # plan away, so advising 'ralph build' would be wrong when the work shipped.
    echo "- [ ] **Open task**" > IMPLEMENTATION_PLAN.md
    touch PROGRESS.md
    run "$RALPH" review
    [[ "$status" -ne 0 ]]
    [[ "$output" == *".ralph/<timestamp>/"* ]]
}

@test "review ignores the Entry Format template entry" {
    # The scaffolded plan carries an example entry at column zero. Counting it
    # as shipped work would send review off to audit the template itself.
    "$RALPH" init
    run "$RALPH" review
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"no shipped items"* ]]
}

@test "review fails while an item is still open" {
    # Review audits finished work. Starting with open items would let it rank
    # its own findings against planning work it never derived.
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n- [ ] **Open task**\n' >> IMPLEMENTATION_PLAN.md
    run "$RALPH" review
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"still holds incomplete items"* ]]
    [[ "$output" == *"Run 'ralph build'"* ]]
}

@test "review is not blocked by superseded items" {
    # '- [~]' marks work that was superseded or blocked. It is neither shipped
    # nor open, so it must not gate a review run either way.
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n- [~] **Superseded task**\n' >> IMPLEMENTATION_PLAN.md
    run "$RALPH" review --dry-run -n 1
    [[ "$status" -eq 0 ]]
}

@test "review gates still fail with no shipped items when -n is passed" {
    # The gates run beside require_init_artifacts, not inside the iteration
    # resolution, so '-n' must not buy a run of empty audit iterations.
    echo "- [ ] **Open task**" > IMPLEMENTATION_PLAN.md
    touch PROGRESS.md
    run "$RALPH" review -n 1
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"no shipped items"* ]]
}

@test "review gates still fail with an open item when -n is passed" {
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n- [ ] **Open task**\n' >> IMPLEMENTATION_PLAN.md
    run "$RALPH" review -n 1
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"still holds incomplete items"* ]]
    [[ "$output" == *"Run 'ralph build'"* ]]
}

@test "review counts shipped items in a plan with no Items heading" {
    # plan_items_body reads the whole file when '## Items' is absent, so plans
    # predating the heading must still satisfy the shipped-items precondition.
    printf -- '# Implementation Plan\n\n- [x] **Shipped task**\n' > IMPLEMENTATION_PLAN.md
    touch PROGRESS.md
    run "$RALPH" review --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[dry-run] Would run: claude -p"* ]]
}

@test "review defaults to 6 iterations" {
    # Review converges like plan, so it takes the same flat cap instead of
    # sizing itself from the plan the way build does.
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n' >> IMPLEMENTATION_PLAN.md
    run "$RALPH" review --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Max:     6 iterations"* ]]
}

@test "review -n overrides the default cap" {
    "$RALPH" init
    printf -- '- [x] **Shipped task**\n' >> IMPLEMENTATION_PLAN.md
    run "$RALPH" review --dry-run -n 2
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Max:     2 iterations"* ]]
}
