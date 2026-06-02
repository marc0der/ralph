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

@test "ralph --help enumerates all supported backends on the -b/--backend line" {
    run "$RALPH" --help
    [[ "$status" -eq 0 ]]
    # Spec (copilot-backend.md): the -b/--backend description must list copilot
    # alongside the existing backends. Assert all three names appear on the
    # backend-flag line so dropping any one trips this test.
    [[ "$output" == *"--backend NAME"*"claude"*"codex"*"copilot"* ]]
}

@test "ralph exits with error for unknown command" {
    run "$RALPH" nonexistent
    [[ "$status" -ne 0 ]]
}
