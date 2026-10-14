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
