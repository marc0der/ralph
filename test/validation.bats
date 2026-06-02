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
