#!/usr/bin/env bats

load test_helper

@test "build rejects non-integer iterations" {
    run "$RALPH" build -n abc
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"iterations must be a positive integer"* ]]
}

@test "build rejects zero iterations" {
    run "$RALPH" build -n 0
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"iterations must be a positive integer"* ]]
}

@test "build rejects negative iterations" {
    run "$RALPH" build -n -1
    [[ "$status" -ne 0 ]]
}

@test "plan rejects non-integer iterations" {
    run "$RALPH" plan -n foo
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"iterations must be a positive integer"* ]]
}

@test "build fails when claude is not in PATH" {
    # Provide init artifacts so iteration calculation succeeds
    echo "- [ ] **Task one**" > IMPLEMENTATION_PLAN.md
    touch PROGRESS.md
    # Keep system paths but remove any directory containing claude
    local filtered_path
    filtered_path=$(echo "$PATH" | tr ':' '\n' | while read -r dir; do
        [[ -x "$dir/claude" ]] || printf "%s:" "$dir"
    done)
    PATH="${filtered_path%:}" run "$RALPH" build
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"'claude' CLI not found"* ]]
}

@test "build -b codex fails when codex is not in PATH" {
    # Provide init artifacts so iteration calculation succeeds
    echo "- [ ] **Task one**" > IMPLEMENTATION_PLAN.md
    touch PROGRESS.md
    # Codex is almost certainly not installed, so just verify the error names the right binary
    local filtered_path
    filtered_path=$(echo "$PATH" | tr ':' '\n' | while read -r dir; do
        [[ -x "$dir/codex" ]] || printf "%s:" "$dir"
    done)
    PATH="${filtered_path%:}" run "$RALPH" build -b codex
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"'codex' CLI not found"* ]]
}

@test "build -b copilot fails when copilot is not in PATH" {
    # Provide init artifacts so iteration calculation succeeds
    echo "- [ ] **Task one**" > IMPLEMENTATION_PLAN.md
    touch PROGRESS.md
    # Copilot is almost certainly not installed, so just verify the error names the right binary
    local filtered_path
    filtered_path=$(echo "$PATH" | tr ':' '\n' | while read -r dir; do
        [[ -x "$dir/copilot" ]] || printf "%s:" "$dir"
    done)
    PATH="${filtered_path%:}" run "$RALPH" build -b copilot
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"'copilot' CLI not found"* ]]
}

@test "build -b pi fails when pi is not in PATH" {
    # Provide init artifacts so iteration calculation succeeds
    echo "- [ ] **Task one**" > IMPLEMENTATION_PLAN.md
    touch PROGRESS.md
    # Pi is preinstalled in the devcontainer image, so we must strip it; on a clean
    # host this is a no-op but still asserts the error names the right binary.
    local filtered_path
    filtered_path=$(echo "$PATH" | tr ':' '\n' | while read -r dir; do
        [[ -x "$dir/pi" ]] || printf "%s:" "$dir"
    done)
    PATH="${filtered_path%:}" run "$RALPH" build -b pi
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"'pi' CLI not found"* ]]
}

@test "build fails outside a git repo" {
    command -v claude >/dev/null 2>&1 || skip "claude CLI not installed"
    cd "$(mktemp -d)" || return 1
    echo "- [ ] **Task one**" > IMPLEMENTATION_PLAN.md
    touch PROGRESS.md
    run "$RALPH" build
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not inside a git repository"* ]]
}

@test "build fails without init artifacts" {
    run "$RALPH" build
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"missing workspace artifacts required for 'build'"* ]]
    [[ "$output" == *"IMPLEMENTATION_PLAN.md"* ]]
    [[ "$output" == *"PROGRESS.md"* ]]
    [[ "$output" == *"Run 'ralph init'"* ]]
}

@test "build fails when only IMPLEMENTATION_PLAN.md is present" {
    echo "- [ ] **Task one**" > IMPLEMENTATION_PLAN.md
    run "$RALPH" build
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"missing workspace artifacts required for 'build'"* ]]
    [[ "$output" == *"PROGRESS.md"* ]]
    [[ "$output" == *"Run 'ralph init'"* ]]
}

@test "plan fails without IMPLEMENTATION_PLAN.md" {
    run "$RALPH" plan
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"missing workspace artifacts required for 'plan'"* ]]
    [[ "$output" == *"IMPLEMENTATION_PLAN.md"* ]]
    [[ "$output" == *"Run 'ralph init'"* ]]
}

@test "build fails with no incomplete items" {
    echo "- [x] **Completed task**" > IMPLEMENTATION_PLAN.md
    touch PROGRESS.md
    run "$RALPH" build
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"no incomplete items"* ]]
}

# Each of these plants a column-zero checkbox in the prose above '## Items'.
# The shipped template indents its own exemplar, so without a decoy these tests
# pass even with the section scoping removed entirely — they would assert
# nothing. The decoy stands in for any checkbox that reaches that half of the
# file: a reworded header, a hand-written plan, or an agent pasting an example
# back at column zero.
plant_decoy_above_items() {
    local decoy='- [ ] **Decoy above the Items heading**'
    awk -v d="$decoy" '/^## Items[[:space:]]*$/ && !done { print d; print ""; done = 1 } { print }' \
        IMPLEMENTATION_PLAN.md > IMPLEMENTATION_PLAN.md.tmp
    mv IMPLEMENTATION_PLAN.md.tmp IMPLEMENTATION_PLAN.md
}

@test "build ignores checkboxes above the Items heading" {
    # Counting them would send the build loop off to implement the template.
    "$RALPH" init
    plant_decoy_above_items
    run "$RALPH" build
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"no incomplete items"* ]]
}

@test "build counts only items below the Items heading" {
    "$RALPH" init
    plant_decoy_above_items
    printf -- '- [ ] **Real task**\n' >> IMPLEMENTATION_PLAN.md
    run "$RALPH" build --dry-run
    [[ "$status" -eq 0 ]]
    # 1 real item + 20% headroom = 2, not 3 (which would include the decoy).
    [[ "$output" == *"Max:     2 iterations"* ]]
}

@test "build announces an item below the heading, not a decoy above it" {
    # next_plan_item shares the same scoping; without it the loop announces —
    # and directs the agent at — whatever checkbox appears first in the file.
    "$RALPH" init
    plant_decoy_above_items
    printf -- '- [ ] **Real task**\n' >> IMPLEMENTATION_PLAN.md
    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Next:    Real task"* ]]
    [[ "$output" != *"Decoy"* ]]
}

@test "build tolerates trailing whitespace on the Items heading" {
    # A stray space must not send counting back to the whole-file fallback,
    # which would re-count everything above the heading.
    "$RALPH" init
    plant_decoy_above_items
    sed -i.bak 's/^## Items$/## Items /' IMPLEMENTATION_PLAN.md && rm -f IMPLEMENTATION_PLAN.md.bak
    printf -- '- [ ] **Real task**\n' >> IMPLEMENTATION_PLAN.md
    run "$RALPH" build --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Max:     2 iterations"* ]]
}

# The other half of the function: a plan with no '## Items' heading is read
# whole, so hand-written and pre-split plans still count.
@test "build counts every item in a plan with no Items heading" {
    "$RALPH" init
    printf -- '- [ ] **One**\n- [ ] **Two**\n' > IMPLEMENTATION_PLAN.md
    run "$RALPH" build --dry-run
    [[ "$status" -eq 0 ]]
    # 2 items + 20% headroom = 3
    [[ "$output" == *"Max:     3 iterations"* ]]
}

@test "build -n overrides calculated iterations" {
    echo "- [ ] **Task one**" > IMPLEMENTATION_PLAN.md
    touch PROGRESS.md
    run "$RALPH" build -n 10 --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Max:     10 iterations"* ]]
}

@test "build calculates iterations from plan with headroom" {
    # 5 items * 1.2 = 6 iterations
    for i in 1 2 3 4 5; do
        echo "- [ ] **Task $i**" >> IMPLEMENTATION_PLAN.md
    done
    touch PROGRESS.md
    run "$RALPH" build --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Max:     6 iterations"* ]]
}
