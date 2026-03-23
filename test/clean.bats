#!/usr/bin/env bats

load test_helper

@test "clean deletes existing artifacts" {
    "$RALPH" init --prompts
    run "$RALPH" clean
    [[ "$status" -eq 0 ]]
    [[ ! -f "IMPLEMENTATION_PLAN.md" ]]
    [[ ! -f "PROGRESS.md" ]]
    [[ ! -f "PROMPT_plan.md" ]]
    [[ ! -f "PROMPT_build.md" ]]
}

@test "clean reports deleted files" {
    "$RALPH" init
    run "$RALPH" clean
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Deleted: IMPLEMENTATION_PLAN.md"* ]]
    [[ "$output" == *"Deleted: PROGRESS.md"* ]]
}

@test "clean handles no artifacts gracefully" {
    run "$RALPH" clean
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Nothing to clean."* ]]
}

@test "clean does not remove specs/ directory" {
    "$RALPH" init
    run "$RALPH" clean
    [[ "$status" -eq 0 ]]
    [[ -d "specs" ]]
}
