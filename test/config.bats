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

# Helper: put a yq on PATH that prints the given version line.
create_fake_yq() {
    mkdir -p "$TEST_DIR/bin"
    printf '#!/usr/bin/env bash\necho "%s"\n' "$1" > "$TEST_DIR/bin/yq"
    chmod +x "$TEST_DIR/bin/yq"
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
