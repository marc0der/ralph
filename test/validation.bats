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
    # Keep system paths but remove any directory containing claude
    local filtered_path
    filtered_path=$(echo "$PATH" | tr ':' '\n' | while read -r dir; do
        [[ -x "$dir/claude" ]] || printf "%s:" "$dir"
    done)
    PATH="${filtered_path%:}" run "$RALPH" build
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"'claude' CLI not found"* ]]
}

@test "build fails outside a git repo" {
    command -v claude >/dev/null 2>&1 || skip "claude CLI not installed"
    cd "$(mktemp -d)" || return 1
    run "$RALPH" build
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not inside a git repository"* ]]
}
