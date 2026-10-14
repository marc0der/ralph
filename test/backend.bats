#!/usr/bin/env bats

load test_helper

@test "default backend is claude when -b flag is not set" {
    "$RALPH" init
    seed_open_item
    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Backend: claude"* ]]
}

@test "-b codex selects codex backend" {
    "$RALPH" init
    seed_open_item
    run "$RALPH" build --dry-run -n 1 -b codex
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Backend: codex"* ]]
    [[ "$output" == *"[dry-run] Would run: codex exec"* ]]
}

@test "unknown backend produces error listing supported backends" {
    "$RALPH" init
    seed_open_item
    run "$RALPH" build --dry-run -n 1 -b unknown
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"unknown backend 'unknown'"* ]]
    [[ "$output" == *"Supported backends:"* ]]
}

@test "dry-run with codex shows default model gpt-5.2-codex" {
    "$RALPH" init
    seed_open_item
    run "$RALPH" build --dry-run -n 1 -b codex
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Model:   gpt-5.2-codex"* ]]
    [[ "$output" == *"gpt-5.2-codex"* ]]
}

@test "dry-run with claude shows default model opus" {
    "$RALPH" init
    seed_open_item
    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Model:   opus"* ]]
}

@test "-m flag overrides default model for any backend" {
    "$RALPH" init
    seed_open_item
    run "$RALPH" build --dry-run -n 1 -b codex -m custom-model
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Model:   custom-model"* ]]
    [[ "$output" == *"custom-model"* ]]
}

@test "-b copilot selects copilot backend" {
    "$RALPH" init
    seed_open_item
    run "$RALPH" build --dry-run -n 1 -b copilot
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Backend: copilot"* ]]
    [[ "$output" == *"[dry-run] Would run: copilot --output-format=json --yolo --model"* ]]
    [[ "$output" == *"-p <prompt>"* ]]
}

@test "dry-run with copilot shows default model claude-sonnet-4.6" {
    "$RALPH" init
    seed_open_item
    run "$RALPH" build --dry-run -n 1 -b copilot
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Model:   claude-sonnet-4.6"* ]]
    [[ "$output" == *"--model claude-sonnet-4.6"* ]]
}

@test "-m flag overrides default model for copilot" {
    "$RALPH" init
    seed_open_item
    run "$RALPH" build --dry-run -n 1 -b copilot -m custom-copilot-model
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Model:   custom-copilot-model"* ]]
    [[ "$output" == *"--model custom-copilot-model"* ]]
}

@test "unknown backend error lists copilot among supported backends" {
    "$RALPH" init
    seed_open_item
    run "$RALPH" build --dry-run -n 1 -b unknown
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Supported backends:"*"copilot"* ]]
}

@test "-b pi selects pi backend" {
    "$RALPH" init
    seed_open_item
    run "$RALPH" build --dry-run -n 1 -b pi
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Backend: pi"* ]]
    # No permission-flag positional, no stray empty arg between --model and --no-session
    [[ "$output" == *"[dry-run] Would run: pi -p --mode json --model anthropic/claude-opus-4-8 --no-session"* ]]
}

@test "dry-run with pi shows default model anthropic/claude-opus-4-8" {
    "$RALPH" init
    seed_open_item
    run "$RALPH" build --dry-run -n 1 -b pi
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Model:   anthropic/claude-opus-4-8"* ]]
    [[ "$output" == *"--model anthropic/claude-opus-4-8"* ]]
}

@test "-m flag overrides default model for pi" {
    "$RALPH" init
    seed_open_item
    run "$RALPH" build --dry-run -n 1 -b pi -m custom-pi-model
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Model:   custom-pi-model"* ]]
    [[ "$output" == *"--model custom-pi-model"* ]]
}

@test "unknown backend error lists pi among supported backends" {
    "$RALPH" init
    seed_open_item
    run "$RALPH" build --dry-run -n 1 -b unknown
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Supported backends:"*"pi"* ]]
}

# Sources ralph without its main dispatch and prints the backend command,
# one argument per line, for backend $1, effort $2 and extra args $3...
backend_cmd() {
    (
        export RALPH_CONFIG_DIR
        eval "$(sed '/^# Main dispatch/,$d' "$RALPH")"
        local name="$1" effort="$2"
        shift 2
        # shellcheck disable=SC2034  # Read by build_backend_cmd
        BACKEND_EXTRA_ARGS=("$@")
        "backend_${name}"
        build_backend_cmd model-x "$effort"
        printf '%s\n' "${BACKEND_CMD[@]}"
    )
}

backend_levels() {
    (
        export RALPH_CONFIG_DIR
        eval "$(sed '/^# Main dispatch/,$d' "$RALPH")"
        local b
        for b in claude codex copilot pi; do
            "backend_${b}"
            echo "${b}: ${BACKEND_EFFORT_LEVELS[*]}"
        done
    )
}

@test "effort: claude appends --effort" {
    run backend_cmd claude high
    [[ "$status" -eq 0 ]]
    [[ "$output" == *$'\n--effort\nhigh' ]]
}

@test "effort: codex appends -c model_reasoning_effort" {
    run backend_cmd codex ultra
    [[ "$status" -eq 0 ]]
    [[ "$output" == *$'\n-c\nmodel_reasoning_effort=ultra' ]]
}

@test "effort: copilot puts --reasoning-effort before the trailing -p" {
    run backend_cmd copilot none
    [[ "$status" -eq 0 ]]
    [[ "$output" == *$'\n--reasoning-effort\nnone\n-p' ]]
}

@test "effort: pi appends --thinking" {
    run backend_cmd pi off
    [[ "$status" -eq 0 ]]
    [[ "$output" == *$'\n--thinking\noff' ]]
}

@test "effort: empty effort adds no effort flag to any backend" {
    local b
    for b in claude codex copilot pi; do
        run backend_cmd "$b" ""
        [[ "$status" -eq 0 ]]
        [[ "$output" != *"effort"* ]]
        [[ "$output" != *"--thinking"* ]]
    done
}

@test "effort: each backend declares the levels of its CLI" {
    run backend_levels
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"claude: low medium high xhigh max"* ]]
    [[ "$output" == *"codex: minimal low medium high xhigh max ultra"* ]]
    [[ "$output" == *"copilot: none minimal low medium high xhigh max"* ]]
    [[ "$output" == *"pi: off minimal low medium high xhigh"* ]]
}

@test "extra args follow the effort flag" {
    run backend_cmd claude low --foo bar
    [[ "$status" -eq 0 ]]
    [[ "$output" == *$'\n--effort\nlow\n--foo\nbar' ]]
}

@test "extra args go before copilot's trailing -p" {
    run backend_cmd copilot "" --foo
    [[ "$status" -eq 0 ]]
    [[ "$output" == *$'\n--foo\n-p' ]]
}

@test "no extra args leaves the command unchanged" {
    run backend_cmd pi ""
    [[ "$status" -eq 0 ]]
    [[ "$output" == $'pi\n-p\n--mode\njson\n--model\nmodel-x\n--no-session' ]]
}
