#!/usr/bin/env bats

load test_helper

@test "build --dry-run prints claude command without executing" {
    "$RALPH" init
    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[dry-run] Would run: claude -p"* ]]
}

@test "build --dry-run prints push command without executing" {
    "$RALPH" init
    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[dry-run] Would run: git push"* ]]
}

@test "build --dry-run shows prompt content" {
    "$RALPH" init
    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[dry-run] Prompt content"* ]]
}

@test "plan --dry-run works" {
    "$RALPH" init
    run "$RALPH" plan --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[dry-run] Would run: claude -p"* ]]
}

@test "build --dry-run respects iteration count" {
    "$RALPH" init
    run "$RALPH" build --dry-run -n 3
    [[ "$status" -eq 0 ]]
    local count
    count=$(echo "$output" | grep -c "\[dry-run\] Would run: claude")
    [[ "$count" -eq 3 ]]
}

@test "build --dry-run includes goal in prompt" {
    "$RALPH" init
    run "$RALPH" build --dry-run -n 1 -g "Add REST endpoint"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Add REST endpoint"* ]]
}
