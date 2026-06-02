#!/usr/bin/env bats

load test_helper

@test "default backend is claude when -b flag is not set" {
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

@test "-b copilot selects copilot backend" {
    "$RALPH" init
    run "$RALPH" build --dry-run -n 1 -b copilot
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Backend: copilot"* ]]
    [[ "$output" == *"[dry-run] Would run: copilot --output-format=json --allow-all --model"* ]]
    [[ "$output" == *"-p <prompt>"* ]]
}

@test "dry-run with copilot shows default model claude-opus-4.7" {
    "$RALPH" init
    run "$RALPH" build --dry-run -n 1 -b copilot
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Model:   claude-opus-4.7"* ]]
    [[ "$output" == *"--model claude-opus-4.7"* ]]
}

@test "-m flag overrides default model for copilot" {
    "$RALPH" init
    run "$RALPH" build --dry-run -n 1 -b copilot -m custom-copilot-model
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Model:   custom-copilot-model"* ]]
    [[ "$output" == *"--model custom-copilot-model"* ]]
}

@test "unknown backend error lists copilot among supported backends" {
    "$RALPH" init
    run "$RALPH" build --dry-run -n 1 -b unknown
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Supported backends:"*"copilot"* ]]
}
