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
    run "$RALPH" plan -n foo -g "the goal"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"iterations must be a positive integer"* ]]
}

@test "build fails when claude is not in PATH" {
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
    run "$RALPH" plan -g "the goal"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"missing workspace artifacts required for 'plan'"* ]]
    [[ "$output" == *"IMPLEMENTATION_PLAN.md"* ]]
    [[ "$output" == *"Run 'ralph init'"* ]]
}

@test "plan fails without a goal" {
    # plan derives its work from the goal, so an absent one is a hard stop,
    # not a default: a bare 'ralph plan' plans against whatever specs/ it
    # resolves, which in a meta repository is the wrong node's.
    "$RALPH" init
    run "$RALPH" plan
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"'plan' requires a goal"* ]]
    [[ "$output" == *"-g <specification or directory>"* ]]
}

@test "plan --dry-run fails without a goal" {
    # --dry-run prints the prompt it would send; with no goal there is no
    # prompt worth printing, so the stop runs before the preview.
    "$RALPH" init
    run "$RALPH" plan --dry-run
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"'plan' requires a goal"* ]]
}

@test "plan -n 1 fails without a goal" {
    # '-n' picks the iteration count, it does not grant permission to run
    # against no goal.
    "$RALPH" init
    run "$RALPH" plan -n 1
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"'plan' requires a goal"* ]]
}

@test "build rejects a goal" {
    # build reads its work from IMPLEMENTATION_PLAN.md, so a goal cannot
    # change what it does. Accepting one silently would let the operator
    # believe the run was steered by it.
    "$RALPH" init
    run "$RALPH" build -g "the goal"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"'build' does not accept -g/--goal"* ]]
    [[ "$output" == *"IMPLEMENTATION_PLAN.md"* ]]
}

@test "review rejects a goal" {
    "$RALPH" init
    run "$RALPH" review -g "the goal"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"'review' does not accept -g/--goal"* ]]
    [[ "$output" == *"IMPLEMENTATION_PLAN.md"* ]]
}

@test "build rejects --goal before any other precondition" {
    # The refusal sits in the option loop, so it fires on an uninitialised
    # workspace too: the flag is wrong whatever the workspace holds.
    run "$RALPH" build --goal "the goal"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"'build' does not accept -g/--goal"* ]]
}

@test "build fails with no incomplete items" {
    echo "- [x] **Completed task**" > IMPLEMENTATION_PLAN.md
    touch PROGRESS.md
    run "$RALPH" build
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"no incomplete items"* ]]
}

@test "build -n 5 fails with no incomplete items" {
    # The hard stop is not part of the iteration heuristic: '-n' picks the
    # iteration count, it does not grant permission to run against no work.
    echo "- [x] **Completed task**" > IMPLEMENTATION_PLAN.md
    touch PROGRESS.md
    run "$RALPH" build -n 5 --dry-run
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"no incomplete items"* ]]
}

@test "build ignores the Entry Format template entry" {
    # The scaffolded plan carries an example entry at column zero. Counting it
    # would send the build loop off to implement the template itself.
    "$RALPH" init
    run "$RALPH" build
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"no incomplete items"* ]]
}

@test "build counts only items below the Items heading" {
    "$RALPH" init
    printf -- '- [ ] **Real task**\n' >> IMPLEMENTATION_PLAN.md
    run "$RALPH" build --dry-run
    [[ "$status" -eq 0 ]]
    # 1 real item + 20% headroom = 2, not 4 (which would include the example).
    [[ "$output" == *"Max:     2 iterations"* ]]
}

@test "build tolerates trailing whitespace on the Items heading" {
    # A stray space must not send counting back to the whole-file fallback,
    # which would re-count the Entry Format exemplar.
    "$RALPH" init
    sed -i.bak 's/^## Items$/## Items /' IMPLEMENTATION_PLAN.md && rm -f IMPLEMENTATION_PLAN.md.bak
    printf -- '- [ ] **Real task**\n' >> IMPLEMENTATION_PLAN.md
    run "$RALPH" build --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Max:     2 iterations"* ]]
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
