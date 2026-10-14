#!/usr/bin/env bats

load test_helper

# Source ralph's functions without its main dispatch, as resolve_prompt.bats does.
ralph_fn() {
    (
        export RALPH_CONFIG_DIR
        eval "$(sed '/^# Main dispatch/,$d' "$RALPH")"
        "$@"
    )
}

# Helper: a PATH without yq, or a skip when yq shares a directory with a tool ralph needs.
path_without_yq() {
    local yq_dir tool
    yq_dir=$(dirname "$(command -v yq)")
    for tool in bash git jq getopt; do
        [[ ! -x "$yq_dir/$tool" ]] || skip "cannot isolate yq from $tool in PATH"
    done
    local filtered_path
    filtered_path=$(path_without yq)
    echo "${filtered_path%:}"
}

@test "resolve_config prints nothing when no config file exists" {
    run ralph_fn resolve_config
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

@test "resolve_config prints the central copy when only it exists" {
    echo "defaults: {}" > "$RALPH_CONFIG_DIR/config.yaml"
    run ralph_fn resolve_config
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$RALPH_CONFIG_DIR/config.yaml" ]]
}

@test "resolve_config prefers the local ralph.yaml over the central copy" {
    echo "defaults: {}" > "$RALPH_CONFIG_DIR/config.yaml"
    echo "defaults: {}" > ralph.yaml
    run ralph_fn resolve_config
    [[ "$status" -eq 0 ]]
    [[ "$output" == "ralph.yaml" ]]
}

@test "config_source_label names local, central and built-in sources" {
    run ralph_fn config_source_label ralph.yaml
    [[ "$output" == "(local)" ]]
    run ralph_fn config_source_label "$RALPH_CONFIG_DIR/config.yaml"
    [[ "$output" == "(central)" ]]
    run ralph_fn config_source_label ""
    [[ "$output" == "built-in (no config file)" ]]
}

@test "build without a config file needs no yq" {
    create_fake_yq "yq 3.4.3"
    "$RALPH" init
    seed_open_item
    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"needs mikefarah yq v4"* ]]
}

@test "build with ralph.yaml and no yq fails naming the file and none" {
    local no_yq_path
    no_yq_path=$(path_without_yq)
    "$RALPH" init
    seed_open_item
    echo "defaults: {}" > ralph.yaml
    PATH="$no_yq_path" run "$RALPH" build
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: ralph.yaml needs mikefarah yq v4 (https://github.com/mikefarah/yq); found: none."* ]]
}

@test "build with the central copy and the Python yq fails naming the version line" {
    create_fake_yq "yq 3.4.3"
    "$RALPH" init
    seed_open_item
    echo "defaults: {}" > "$RALPH_CONFIG_DIR/config.yaml"
    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --dry-run
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: $RALPH_CONFIG_DIR/config.yaml needs mikefarah yq v4"*"found: yq 3.4.3."* ]]
}

@test "build with mikefarah yq v3 fails the version check" {
    create_fake_yq "yq version 3.4.1 (https://github.com/mikefarah/yq/)"
    "$RALPH" init
    seed_open_item
    echo "defaults: {}" > ralph.yaml
    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build --dry-run
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"found: yq version 3.4.1"* ]]
}

@test "build with ralph.yaml and mikefarah yq v4 runs" {
    require_yq_or_skip
    "$RALPH" init
    seed_open_item
    echo "defaults: {}" > ralph.yaml
    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[dry-run] Would run"* ]]
}

@test "build with a ralph.yaml that is not YAML fails naming the file" {
    require_yq_or_skip
    "$RALPH" init
    seed_open_item
    echo "defaults: [" > ralph.yaml
    run "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: ralph.yaml is not valid YAML"* ]]
}

@test "config_json converts the file to JSON once and reads the cache after" {
    require_yq_or_skip
    printf 'build:\n  model: opus\n' > ralph.yaml
    run ralph_fn eval 'config_json ralph.yaml >/dev/null; rm ralph.yaml; config_json ralph.yaml | jq -r .build.model'
    [[ "$status" -eq 0 ]]
    [[ "$output" == "opus" ]]
}

@test "config_get prints nothing when no config file exists" {
    run ralph_fn config_get build model
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

@test "config_get reads the section before defaults" {
    require_yq_or_skip
    printf 'defaults:\n  model: sonnet\nbuild:\n  model: opus\n' > ralph.yaml
    run ralph_fn config_get build model
    [[ "$output" == "opus" ]]
    run ralph_fn config_get plan model
    [[ "$output" == "sonnet" ]]
}

@test "config_get prints nothing for a key no section sets" {
    require_yq_or_skip
    printf 'defaults:\n  model: sonnet\nreview:\n' > ralph.yaml
    run ralph_fn config_get review effort
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

@test "config_get inherits false booleans and prints lists one item per line" {
    require_yq_or_skip
    printf 'defaults:\n  metrics: false\n  extra_args: [--a, --b]\nbuild:\n  quiet: false\n' > ralph.yaml
    run ralph_fn config_get build metrics
    [[ "$output" == "false" ]]
    run ralph_fn config_get build quiet
    [[ "$output" == "false" ]]
    run ralph_fn config_get build extra_args
    [[ "$output" == $'--a\n--b' ]]
}

@test "config_get inherits the backend from defaults" {
    require_yq_or_skip
    printf 'defaults:\n  backend: codex\n' > ralph.yaml
    run ralph_fn config_get fix backend
    [[ "$output" == "codex" ]]
}

@test "config_get blocks backend-tied keys when the section changes backend" {
    require_yq_or_skip
    printf 'defaults:\n  model: opus\n  effort: max\n  extra_args: [--x]\n  quiet: true\nbuild:\n  backend: codex\n' > ralph.yaml
    run --separate-stderr ralph_fn config_get build model
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
    [[ -z "$stderr" ]]
    run ralph_fn config_get build effort
    [[ -z "$output" ]]
    run ralph_fn config_get build extra_args
    [[ -z "$output" ]]
    run ralph_fn config_get build quiet
    [[ "$output" == "true" ]]
}

@test "config_get keeps the section's own backend-tied keys after a backend change" {
    require_yq_or_skip
    printf 'defaults:\n  model: opus\nbuild:\n  backend: codex\n  effort: high\n' > ralph.yaml
    run ralph_fn config_get build effort
    [[ "$output" == "high" ]]
}

@test "config_get keeps inheritance when the section names the defaults backend" {
    require_yq_or_skip
    printf 'defaults:\n  backend: codex\n  model: gpt-5\nplan:\n  backend: codex\nbuild:\n  backend: claude\n' > ralph.yaml
    run ralph_fn config_get plan model
    [[ "$output" == "gpt-5" ]]
    run ralph_fn config_get build model
    [[ -z "$output" ]]
}

@test "config_get treats an unset defaults backend as claude" {
    require_yq_or_skip
    printf 'defaults:\n  model: opus\nreview:\n  backend: claude\nfix:\n  backend: pi\n' > ralph.yaml
    run ralph_fn config_get review model
    [[ "$output" == "opus" ]]
    run ralph_fn config_get fix model
    [[ -z "$output" ]]
}

# Helper: run build --dry-run over a ralph.yaml holding the given text.
run_build_with_config() {
    "$RALPH" init
    seed_open_item
    printf '%b' "$1" > ralph.yaml
    run --separate-stderr "$RALPH" build --dry-run -n 1
}

@test "validate_config rejects review.iterations under build --dry-run" {
    require_yq_or_skip
    run_build_with_config 'review:\n  iterations: 2\n'
    [[ "$status" -eq 1 ]]
    [[ "$stderr" == *"Error: ralph.yaml: review.iterations is not allowed; review runs one pass."* ]]
    [[ "$output" != *"[dry-run] Would run"* ]]
}

@test "validate_config rejects a top level that is not a map" {
    require_yq_or_skip
    run_build_with_config '- build\n'
    [[ "$status" -eq 1 ]]
    [[ "$stderr" == *"Error: ralph.yaml: the top level is not a map."* ]]
}

@test "validate_config rejects an unknown section and a section that is not a map" {
    require_yq_or_skip
    run_build_with_config 'builds:\n  model: opus\nplan: 3\n'
    [[ "$status" -eq 1 ]]
    [[ "$stderr" == *"Error: ralph.yaml: builds is not a known section."* ]]
    [[ "$stderr" == *"Error: ralph.yaml: plan is not a map."* ]]
}

@test "validate_config rejects an unknown key in a section the run does not read" {
    require_yq_or_skip
    run_build_with_config 'fix:\n  noop_patiance: 3\n'
    [[ "$status" -eq 1 ]]
    [[ "$stderr" == *"Error: ralph.yaml: fix.noop_patiance is not a known key."* ]]
}

@test "validate_config rejects wrong types and out-of-range values" {
    require_yq_or_skip
    run_build_with_config 'build:\n  model: ""\n  metrics: 1\n  extra_args: [1]\n  noop_patience: 0\n  headroom_pct: -1\n  effort: 3\nplan:\n  iterations: 2.5\n'
    [[ "$status" -eq 1 ]]
    [[ "$stderr" == *"build.model must be a non-empty string; got \"\"."* ]]
    [[ "$stderr" == *"build.metrics must be true or false; got 1."* ]]
    [[ "$stderr" == *"build.extra_args must be a list of strings; got [1]."* ]]
    [[ "$stderr" == *"build.noop_patience must be a positive integer; got 0."* ]]
    [[ "$stderr" == *"build.headroom_pct must be a non-negative integer; got -1."* ]]
    [[ "$stderr" == *"build.effort must be a string; got 3."* ]]
    [[ "$stderr" == *"plan.iterations must be a positive integer; got 2.5."* ]]
}

@test "validate_config rejects a key outside its phases" {
    require_yq_or_skip
    run_build_with_config 'plan:\n  headroom_pct: 10\n'
    [[ "$status" -eq 1 ]]
    [[ "$stderr" == *"Error: ralph.yaml: plan.headroom_pct is not allowed in plan; set it under build or fix."* ]]
}

@test "validate_config rejects a phase-limited key in defaults" {
    require_yq_or_skip
    "$RALPH" init
    seed_open_item
    printf 'defaults:\n  skip_push: true\n  iterations: 3\n' > "$RALPH_CONFIG_DIR/config.yaml"
    run --separate-stderr "$RALPH" build --dry-run -n 1
    [[ "$status" -eq 1 ]]
    [[ "$stderr" == *"Error: $RALPH_CONFIG_DIR/config.yaml: defaults.skip_push is not allowed in defaults; set it under build or fix."* ]]
    [[ "$stderr" == *"defaults.iterations is not allowed in defaults; set it under plan, build or fix."* ]]
}

@test "validate_config rejects iterations beside headroom_pct or noop_patience" {
    require_yq_or_skip
    run_build_with_config 'build:\n  iterations: 3\n  headroom_pct: 10\nfix:\n  iterations: 3\n  noop_patience: 2\n'
    [[ "$status" -eq 1 ]]
    [[ "$stderr" == *"Error: ralph.yaml: build sets iterations with headroom_pct; iterations turns self-sizing off."* ]]
    [[ "$stderr" == *"Error: ralph.yaml: fix sets iterations with noop_patience; iterations turns self-sizing off."* ]]
}

@test "validate_config rejects an unsupported backend" {
    require_yq_or_skip
    run_build_with_config 'review:\n  backend: gpt\n'
    [[ "$status" -eq 1 ]]
    [[ "$stderr" == *"Error: ralph.yaml: review.backend must be one of: claude codex copilot pi; got \"gpt\"."* ]]
}

@test "validate_config checks effort against the section's resolved backend" {
    require_yq_or_skip
    run_build_with_config 'defaults:\n  backend: pi\nplan:\n  effort: max\nreview:\n  backend: claude\n  effort: max\n'
    [[ "$status" -eq 1 ]]
    [[ "$stderr" == *"Error: ralph.yaml: plan.effort 'max' is not a pi level; use one of: off minimal low medium high xhigh."* ]]
    [[ "$stderr" != *"review.effort"* ]]
}

@test "validate_config checks defaults effort against claude when no backend is set" {
    require_yq_or_skip
    run_build_with_config 'defaults:\n  effort: ultra\n'
    [[ "$status" -eq 1 ]]
    [[ "$stderr" == *"Error: ralph.yaml: defaults.effort 'ultra' is not a claude level"* ]]
}

@test "validate_config accepts an effort the backend change stops inheriting" {
    require_yq_or_skip
    run_build_with_config 'defaults:\n  effort: max\nbuild:\n  backend: pi\n'
    [[ "$status" -eq 0 ]]
    [[ "$stderr" != *"Error:"* ]]
}

@test "validate_config accepts an empty file" {
    require_yq_or_skip
    run_build_with_config ''
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[dry-run] Would run"* ]]
}

@test "validate_config treats a null key and a null section as absent" {
    require_yq_or_skip
    run_build_with_config 'defaults:\nreview:\nbuild:\n  model:\n  iterations: 3\n  headroom_pct:\n'
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"[dry-run] Would run"* ]]
}

@test "build applies the file's backend, model, effort and extra_args" {
    require_yq_or_skip
    run_build_with_config 'build:\n  backend: codex\n  model: gpt-x\n  effort: ultra\n  extra_args: [--foo, bar]\n'
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Model:   gpt-x"* ]]
    [[ "$output" == *"Would run: codex exec "*" --model gpt-x -c model_reasoning_effort=ultra --foo bar <prompt>"* ]]
}

@test "a local file omitting a key takes the built-in default, not the central value" {
    require_yq_or_skip
    printf 'defaults:\n  model: haiku\n' > "$RALPH_CONFIG_DIR/config.yaml"
    run_build_with_config 'build:\n  effort: low\n'
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Model:   opus"* ]]
    [[ "$output" != *"haiku"* ]]
}

@test "-m and -e beat the file's model and effort" {
    require_yq_or_skip
    "$RALPH" init
    seed_open_item
    printf 'defaults:\n  model: opus\n  effort: max\n' > ralph.yaml
    run --separate-stderr "$RALPH" build --dry-run -n 1 -m haiku -e low
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"--model haiku "*"--effort low"* ]]
    [[ "$output" != *"opus"* && "$output" != *"max"* ]]
}

@test "-b to another backend drops the file's tied keys and warns naming only those set" {
    require_yq_or_skip
    "$RALPH" init
    seed_open_item
    printf 'build:\n  model: opus\n  effort: max\n' > ralph.yaml
    run --separate-stderr "$RALPH" build --dry-run -n 1 -b codex
    [[ "$status" -eq 0 ]]
    [[ "$stderr" == *"Warning: -b codex overrides config backend 'claude' for build; dropped model 'opus', effort 'max'."* ]]
    [[ "$stderr" != *"extra_args"* ]]
    [[ "$output" == *"Would run: codex exec "*" --model gpt-5.2-codex <prompt>"* ]]
    [[ "$output" != *"model_reasoning_effort"* ]]
}

@test "-b to another backend names dropped extra_args and keeps -m" {
    require_yq_or_skip
    "$RALPH" init
    seed_open_item
    printf 'defaults:\n  extra_args: [--foo, bar]\n' > ralph.yaml
    run --separate-stderr "$RALPH" build --dry-run -n 1 -b pi -m my-model
    [[ "$status" -eq 0 ]]
    [[ "$stderr" == *"for build; dropped extra_args '--foo bar'."* ]]
    [[ "$output" == *"Model:   my-model"* ]]
    [[ "$output" != *"--foo"* ]]
}

@test "-b prints no warning when the file sets no tied key or names the same backend" {
    require_yq_or_skip
    "$RALPH" init
    seed_open_item
    printf 'build:\n  quiet: false\n' > ralph.yaml
    run --separate-stderr "$RALPH" build --dry-run -n 1 -b codex
    [[ "$status" -eq 0 ]]
    [[ "$stderr" != *"Warning: -b"* ]]
    printf 'build:\n  backend: codex\n  model: gpt-x\n' > ralph.yaml
    run --separate-stderr "$RALPH" build --dry-run -n 1 -b codex
    [[ "$status" -eq 0 ]]
    [[ "$stderr" != *"Warning: -b"* ]]
    [[ "$output" == *"Model:   gpt-x"* ]]
}

@test "a section that changes backend uses no defaults tied key and prints no warning" {
    require_yq_or_skip
    run_build_with_config 'defaults:\n  model: opus\n  extra_args: [--foo]\nbuild:\n  backend: codex\n'
    [[ "$status" -eq 0 ]]
    [[ "$stderr" != *"Warning"* ]]
    [[ "$output" == *"Would run: codex exec "*" --model gpt-5.2-codex <prompt>"* ]]
    [[ "$output" != *"--foo"* ]]
}

@test "quiet from the file hides live lines, and --verbose overrides it" {
    require_yq_or_skip
    "$RALPH" init
    seed_open_item
    create_streaming_backend
    printf 'build:\n  quiet: true\n' > ralph.yaml
    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$stderr" != *"→ Bash ls -la"* ]]
    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --skip-push --verbose
    [[ "$status" -eq 0 ]]
    [[ "$stderr" == *"→ Bash ls -la"* ]]
}

@test "metrics from the file disables capture, and --metrics overrides it" {
    require_yq_or_skip
    "$RALPH" init
    seed_open_item
    create_streaming_backend
    printf 'defaults:\n  metrics: false\n' > ralph.yaml
    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push
    [[ "$status" -eq 0 ]]
    [[ ! -d .ralph/metrics ]]
    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --skip-push --metrics
    [[ "$status" -eq 0 ]]
    compgen -G '.ralph/metrics/*/metrics.jsonl' >/dev/null
}

@test "skip_push from the file skips the push, and --push overrides it" {
    require_yq_or_skip
    "$RALPH" init
    seed_open_item
    create_streaming_backend
    printf 'build:\n  skip_push: true\n' > ralph.yaml
    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --no-metrics
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"No 'origin' remote"* ]]
    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" build -n 1 --no-metrics --push
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"No 'origin' remote — skipping push."* ]]
}

@test "the Config block names the built-in source and prints under --quiet and --dry-run" {
    "$RALPH" init
    seed_open_item
    run --separate-stderr "$RALPH" build --dry-run -q
    [[ "$status" -eq 0 ]]
    [[ "$stderr" == *"Config: built-in (no config file) [build]
  backend=claude model=opus effort=default
  iterations=auto(2) headroom=20% patience=2 push=on metrics=off (dry-run) quiet=on"* ]]
    [[ "$output" != *"Config:"* ]]
}

@test "the Config block names the local and central sources" {
    require_yq_or_skip
    "$RALPH" init
    seed_open_item
    printf 'build:\n  effort: high\n' > "$RALPH_CONFIG_DIR/config.yaml"
    run --separate-stderr "$RALPH" build --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$stderr" == *"Config: $RALPH_CONFIG_DIR/config.yaml (central) [build]"* ]]
    [[ "$stderr" == *"effort=high"* ]]
    printf 'build:\n  skip_push: true\n  quiet: true\n' > ralph.yaml
    run --separate-stderr "$RALPH" build --dry-run -n 3 -b codex -m gpt-x
    [[ "$status" -eq 0 ]]
    [[ "$stderr" == *"Config: ./ralph.yaml (local) [build]
  backend=codex model=gpt-x effort=default
  iterations=3 headroom=20% patience=2 push=off metrics=off (dry-run) quiet=on"* ]]
}

@test "the Config block prints the plan cap and review's single pass without build tuning" {
    "$RALPH" init
    run --separate-stderr "$RALPH" plan --dry-run -g goal --verbose -e low
    [[ "$status" -eq 0 ]]
    [[ "$stderr" == *"Config: built-in (no config file) [plan]
  backend=claude model=opus effort=low
  iterations=6 metrics=off (dry-run) quiet=off"* ]]
    seed_shipped_item
    seed_cycle_base
    run --separate-stderr "$RALPH" review --dry-run -q
    [[ "$status" -eq 0 ]]
    [[ "$stderr" == *"[review]"*"iterations=1 metrics=off (dry-run) quiet=on"* ]]
    [[ "$stderr" != *"headroom="* && "$stderr" != *"push="* ]]
}

@test "the Config block prints metrics on and off for a real run" {
    "$RALPH" init
    seed_open_item
    create_streaming_backend
    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --skip-push
    [[ "$status" -eq 0 ]]
    [[ "$stderr" == *"iterations=1 headroom=20% patience=2 push=off metrics=on quiet=off"* ]]
    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build -n 1 --skip-push --no-metrics
    [[ "$status" -eq 0 ]]
    [[ "$stderr" == *"push=off metrics=off quiet=off"* ]]
}

@test "plan.iterations replaces the plan cap" {
    require_yq_or_skip
    "$RALPH" init
    printf 'plan:\n  iterations: 2\n' > ralph.yaml
    run --separate-stderr "$RALPH" plan --dry-run -g goal
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Max:     2 iterations"* ]]
    [[ "$stderr" == *"iterations=2 metrics="* ]]
}

@test "build.iterations replaces the calculated count and turns off the noop exit" {
    require_yq_or_skip
    "$RALPH" init
    seed_open_item
    create_streaming_backend
    printf 'build:\n  iterations: 3\n' > ralph.yaml
    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build --skip-push --no-metrics
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Max:     3 iterations"* ]]
    [[ "$output" == *"ITERATION 3 / 3"* ]]
    [[ "$output" != *"No changes detected"* ]]
    [[ "$stderr" == *"iterations=3 headroom=20% patience=2"* ]]
}

@test "-n beats build.iterations" {
    require_yq_or_skip
    "$RALPH" init
    seed_open_item
    printf 'build:\n  iterations: 3\n' > ralph.yaml
    run "$RALPH" build --dry-run -n 5
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Max:     5 iterations"* ]]
}

@test "headroom_pct sizes the build count" {
    require_yq_or_skip
    "$RALPH" init
    for _ in 1 2 3 4; do seed_open_item; done
    printf 'build:\n  headroom_pct: 50\n' > ralph.yaml
    run --separate-stderr "$RALPH" build --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Max:     6 iterations"* ]]
    [[ "$stderr" == *"iterations=auto(6) headroom=50% patience=2"* ]]
    printf 'build:\n  headroom_pct: 0\n' > ralph.yaml
    run "$RALPH" build --dry-run
    [[ "$output" == *"Max:     4 iterations"* ]]
}

@test "calculate_build_iterations rounds the headroom up" {
    "$RALPH" init
    for _ in 1 2 3; do seed_open_item; done
    run ralph_fn calculate_build_iterations 20
    [[ "$output" == "4" ]]
    run ralph_fn calculate_build_iterations 10
    [[ "$output" == "4" ]]
    run ralph_fn calculate_build_iterations 0
    [[ "$output" == "3" ]]
}

@test "noop_patience sets the consecutive noops before the early exit" {
    require_yq_or_skip
    "$RALPH" init
    for _ in 1 2 3 4 5; do seed_open_item; done
    create_streaming_backend
    printf 'build:\n  noop_patience: 3\n' > ralph.yaml
    PATH="$TEST_DIR/bin:$PATH" run --separate-stderr "$RALPH" build --skip-push --no-metrics
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"No changes detected for 3 consecutive iterations — exiting early."* ]]
    [[ "$output" == *"ITERATION 3 / 6"* ]]
    [[ "$output" != *"ITERATION 4 / 6"* ]]
    [[ "$stderr" == *"patience=3 push=off"* ]]
}

@test "fix --dry-run runs build mode under the fix section" {
    "$RALPH" init
    seed_open_item
    run --separate-stderr "$RALPH" fix --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Mode:    build"* ]]
    [[ "$stderr" == *"Config: built-in (no config file) [fix]"* ]]
    [[ "$stderr" == *"iterations=auto(2) headroom=20% patience=2 push=on"* ]]
}

@test "fix reads the fix section and not the build section" {
    require_yq_or_skip
    "$RALPH" init
    seed_open_item
    printf 'build:\n  iterations: 3\nfix:\n  iterations: 5\n  effort: low\n' > ralph.yaml
    run --separate-stderr "$RALPH" fix --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Max:     5 iterations"* ]]
    [[ "$stderr" == *"effort=low"* ]]
    run "$RALPH" build --dry-run
    [[ "$output" == *"Max:     3 iterations"* ]]
}

@test "fix uses the build prompt, writes .ralph/cycle-base and pushes" {
    "$RALPH" init
    seed_open_item
    create_committing_backend
    git init --bare --quiet "$TEST_DIR/remote.git"
    git remote add origin "$TEST_DIR/remote.git"
    local head
    head=$(git rev-parse HEAD)
    PATH="$TEST_DIR/bin:$PATH" run "$RALPH" fix -n 1 --no-metrics
    [[ "$status" -eq 0 ]]
    [[ "$(cat .ralph/cycle-base)" == ". $head" ]]
    [[ "$(git rev-parse HEAD)" != "$head" ]]
    [[ "$(git --git-dir="$TEST_DIR/remote.git" rev-parse "$(git branch --show-current)")" == "$(git rev-parse HEAD)" ]]
}

@test "fix stops on a plan with no open item" {
    "$RALPH" init
    run "$RALPH" fix --dry-run
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: no incomplete items in IMPLEMENTATION_PLAN.md. Run 'ralph plan' first."* ]]
}

@test "fix names fix in the goal refusal" {
    "$RALPH" init
    seed_open_item
    run "$RALPH" fix -g x --dry-run
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: 'fix' does not accept -g/--goal"* ]]
}

@test "fix names fix in the missing artifacts error" {
    "$RALPH" init
    seed_open_item
    rm PROGRESS.md
    run "$RALPH" fix --dry-run
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"missing workspace artifacts required for 'fix': PROGRESS.md"* ]]
    [[ "$output" == *"before running 'ralph fix'"* ]]
}

@test "install.sh installs config.yaml over the old central copy" {
    echo "stale: true" > "$RALPH_CONFIG_DIR/config.yaml"
    RALPH_BIN_DIR="$TEST_DIR/install-bin" run "$BATS_TEST_DIRNAME/../install.sh"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Config:     $RALPH_CONFIG_DIR/config.yaml"* ]]
    cmp "$BATS_TEST_DIRNAME/../config.yaml" "$RALPH_CONFIG_DIR/config.yaml"
}

@test "install.sh warns when mikefarah yq v4 is absent" {
    create_fake_yq "yq 3.4.3"
    PATH="$TEST_DIR/bin:$PATH" RALPH_BIN_DIR="$TEST_DIR/install-bin" run "$BATS_TEST_DIRNAME/../install.sh"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Warning: ralph needs mikefarah yq v4 to read config.yaml; install it or remove $RALPH_CONFIG_DIR/config.yaml."* ]]
}

@test "install.sh warns when mikefarah yq is version 3" {
    create_fake_yq "yq version 3.4.1 (https://github.com/mikefarah/yq/)"
    PATH="$TEST_DIR/bin:$PATH" RALPH_BIN_DIR="$TEST_DIR/install-bin" run "$BATS_TEST_DIRNAME/../install.sh"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Warning: ralph needs mikefarah yq v4 to read config.yaml; install it or remove $RALPH_CONFIG_DIR/config.yaml."* ]]
}

@test "install.sh prints no yq warning with mikefarah yq v4" {
    require_yq_or_skip
    RALPH_BIN_DIR="$TEST_DIR/install-bin" run "$BATS_TEST_DIRNAME/../install.sh"
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"needs mikefarah yq v4"* ]]
}

@test "the shipped config.yaml validates and sets no backend-tied key" {
    require_yq_or_skip
    cp "$BATS_TEST_DIRNAME/../config.yaml" "$RALPH_CONFIG_DIR/config.yaml"
    "$RALPH" init
    seed_open_item
    run --separate-stderr "$RALPH" build -b codex --dry-run
    [[ "$status" -eq 0 ]]
    [[ "$stderr" == *"Config: $RALPH_CONFIG_DIR/config.yaml (central) [build]"* ]]
    [[ "$stderr" != *"overrides config backend"* ]]
}

# Helper: the Config block of a --dry-run in each phase, with the source label cut.
# Review runs first, while the plan holds no open item; plan, build and fix follow one.
dry_run_config_blocks() {
    local phase config_stderr
    grep -v '^- \[ \]' IMPLEMENTATION_PLAN.md > plan.tmp && mv plan.tmp IMPLEMENTATION_PLAN.md
    for phase in review plan build fix; do
        [[ "$phase" == plan ]] && seed_open_item
        local args=()
        [[ "$phase" == plan ]] && args=(-g goal)
        config_stderr=$("$RALPH" "$phase" --dry-run "${args[@]}" 2>&1 >/dev/null) || return 1
        awk '/^Config: /{sub(/^Config: .* \[/, "["); n = 3} n-- > 0' <<< "$config_stderr"
    done
}

@test "the shipped config.yaml drifts from no built-in in plan, build, fix and review" {
    require_yq_or_skip
    "$RALPH" init
    seed_shipped_item
    seed_cycle_base
    cp "$BATS_TEST_DIRNAME/../config.yaml" "$RALPH_CONFIG_DIR/config.yaml"
    local shipped builtin
    shipped=$(dry_run_config_blocks)
    rm "$RALPH_CONFIG_DIR/config.yaml"
    builtin=$(dry_run_config_blocks)
    [[ "$(grep -c '^\[' <<< "$shipped")" -eq 4 ]]
    [[ "$shipped" == "[review]"*"[plan]"*"[build]"*"[fix]"* ]]
    [[ "$shipped" == "$builtin" ]]
}
