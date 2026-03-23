#!/usr/bin/env bats

load test_helper

@test "ralph prints usage with no arguments" {
    run "$RALPH"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Usage:"* ]]
}

@test "ralph prints usage with --help" {
    run "$RALPH" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Usage:"* ]]
}

@test "ralph exits with error for unknown command" {
    run "$RALPH" nonexistent
    [[ "$status" -ne 0 ]]
}
