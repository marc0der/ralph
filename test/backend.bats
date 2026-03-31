#!/usr/bin/env bats

load test_helper

@test "default backend is claude when neither -b nor RALPH_BACKEND is set" {
    "$RALPH" init
    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Backend: claude"* ]]
}

@test "-b codex selects codex backend" {
    "$RALPH" init
    run "$RALPH" build --dry-run -n 1 -b codex
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Backend: codex"* ]]
    [[ "$output" == *"[dry-run] Would run: codex exec"* ]]
}

@test "RALPH_BACKEND=codex env var selects codex backend" {
    "$RALPH" init
    RALPH_BACKEND=codex run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Backend: codex"* ]]
}

@test "-b claude takes precedence over RALPH_BACKEND=codex" {
    "$RALPH" init
    RALPH_BACKEND=codex run "$RALPH" build --dry-run -n 1 -b claude
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Backend: claude"* ]]
}

@test "unknown backend produces error listing supported backends" {
    "$RALPH" init
    run "$RALPH" build --dry-run -n 1 -b unknown
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"unknown backend 'unknown'"* ]]
    [[ "$output" == *"Supported backends:"* ]]
}

@test "dry-run with codex shows default model gpt-5.2-codex" {
    "$RALPH" init
    run "$RALPH" build --dry-run -n 1 -b codex
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Model:   gpt-5.2-codex"* ]]
    [[ "$output" == *"gpt-5.2-codex"* ]]
}

@test "dry-run with claude shows default model opus" {
    "$RALPH" init
    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Model:   opus"* ]]
}

@test "-m flag overrides default model for any backend" {
    "$RALPH" init
    run "$RALPH" build --dry-run -n 1 -b codex -m custom-model
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Model:   custom-model"* ]]
    [[ "$output" == *"custom-model"* ]]
}
