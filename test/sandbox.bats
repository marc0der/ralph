#!/usr/bin/env bats

load test_helper

# Helper: build a PATH that hides a specific command
path_without() {
    local cmd="$1"
    echo "$PATH" | tr ':' '\n' | while read -r dir; do
        [[ -x "$dir/$cmd" ]] || printf "%s:" "$dir"
    done
}

@test "sandbox fails when devcontainer CLI is not found" {
    local filtered_path
    filtered_path=$(path_without devcontainer)
    PATH="${filtered_path%:}" run "$RALPH" sandbox
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"'devcontainer' CLI not found"* ]]
}

@test "sandbox clean fails when docker is not found" {
    # Skip if docker and bash share a directory (NixOS profile paths)
    local docker_dir bash_dir
    docker_dir=$(dirname "$(command -v docker)")
    bash_dir=$(dirname "$(command -v bash)")
    [[ "$docker_dir" != "$bash_dir" ]] || skip "cannot isolate docker from bash in PATH"
    local filtered_path
    filtered_path=$(path_without docker)
    PATH="${filtered_path%:}" run "$RALPH" sandbox clean
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"'docker' not found"* ]]
}

@test "sandbox --rebuild fails when devcontainer CLI is not found" {
    local filtered_path
    filtered_path=$(path_without devcontainer)
    PATH="${filtered_path%:}" run "$RALPH" sandbox --rebuild
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"'devcontainer' CLI not found"* ]]
}

@test "sandbox fails outside a git repo" {
    command -v devcontainer >/dev/null 2>&1 || skip "devcontainer CLI not installed"
    cd "$(mktemp -d)" || return 1
    run "$RALPH" sandbox
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not inside a git repository"* ]]
}

@test "sandbox fails when config is missing" {
    command -v devcontainer >/dev/null 2>&1 || skip "devcontainer CLI not installed"
    export RALPH_CONFIG_DIR="$TEST_DIR/.ralph-empty"
    mkdir -p "$RALPH_CONFIG_DIR"
    run "$RALPH" sandbox
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"devcontainer config not found"* ]]
}

@test "sandbox rejects unknown option" {
    run "$RALPH" sandbox --bogus
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"unknown sandbox option"* ]]
}

@test "usage includes sandbox command" {
    run "$RALPH" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"sandbox"* ]]
}

@test "usage includes sandbox clean" {
    run "$RALPH" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"sandbox clean"* ]]
}

@test "usage includes sandbox --rebuild" {
    run "$RALPH" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--rebuild"* ]]
}
