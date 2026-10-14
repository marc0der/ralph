#!/usr/bin/env bats

load test_helper

@test "clean deletes existing artifacts" {
    "$RALPH" init
    run "$RALPH" clean
    [[ "$status" -eq 0 ]]
    [[ ! -f "IMPLEMENTATION_PLAN.md" ]]
    [[ ! -f "PROGRESS.md" ]]
}

@test "clean preserves local prompt templates" {
    "$RALPH" init --prompts
    run "$RALPH" clean
    [[ "$status" -eq 0 ]]
    [[ -f "PROMPT_plan.md" ]]
    [[ -f "PROMPT_build.md" ]]
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

@test "clean leaves ralph.yaml in place" {
    "$RALPH" init
    echo "defaults: {}" > ralph.yaml
    run "$RALPH" clean
    [[ "$status" -eq 0 ]]
    [[ "$(cat ralph.yaml)" == "defaults: {}" ]]
    [[ "$output" != *"ralph.yaml"* ]]
}
