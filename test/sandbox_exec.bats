#!/usr/bin/env bats

load test_helper

TOKEN="sk-ant-oat01-$(printf 'a%.0s' {1..95})"

# Mocks devcontainer, docker and gh, and logs every call. docker exec also
# records the value of each credential variable it received in its environment,
# so a test can tell "passed as a name, read from the environment" apart from
# "written into the argument list".
setup_exec_mock() {
    local mock_bin="$TEST_DIR/mock-bin"
    mkdir -p "$mock_bin"
    export DEVCONTAINER_CALL_LOG="$TEST_DIR/devcontainer.log"
    export DOCKER_CALL_LOG="$TEST_DIR/docker.log"
    export DOCKER_ENV_LOG="$TEST_DIR/docker-env.log"

    cat > "$mock_bin/devcontainer" << 'MOCKEOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$DEVCONTAINER_CALL_LOG"
printf -- '---\n' >> "$DEVCONTAINER_CALL_LOG"
echo '{"outcome":"success"}'
exit 0
MOCKEOF

    cat > "$mock_bin/docker" << 'MOCKEOF'
#!/usr/bin/env bash
case "$1" in
    ps)   echo "cid123"; exit 0 ;;
    exec)
        printf '%s\n' "$@" >> "$DOCKER_CALL_LOG"
        printf -- '---\n' >> "$DOCKER_CALL_LOG"
        for v in CLAUDE_CODE_OAUTH_TOKEN GH_TOKEN ANTHROPIC_API_KEY; do
            [[ -n "${!v:-}" ]] && printf '%s=%s\n' "$v" "${!v}" >> "$DOCKER_ENV_LOG"
        done
        exit "${MOCK_DOCKER_EXEC_STATUS:-0}" ;;
esac
exit 0
MOCKEOF

    cat > "$mock_bin/gh" << 'MOCKEOF'
#!/usr/bin/env bash
[[ "$1 $2" == "auth token" ]] || exit 0
if [[ -n "${MOCK_GH_AUTH_TOKEN:-}" ]]; then
    printf '%s\n' "$MOCK_GH_AUTH_TOKEN"
    exit 0
fi
exit 1
MOCKEOF
    chmod +x "$mock_bin/devcontainer" "$mock_bin/docker" "$mock_bin/gh"
    ln -s "$RALPH" "$mock_bin/ralph"

    # shellcheck disable=SC2031
    mkdir -p "$RALPH_CONFIG_DIR/container"
    # shellcheck disable=SC2031
    echo '{}' > "$RALPH_CONFIG_DIR/container/devcontainer.json"
    export PATH="$mock_bin:$PATH"
    unset SSH_AUTH_SOCK CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY GH_TOKEN GITHUB_TOKEN MOCK_GH_AUTH_TOKEN
}

save_token() {
    # shellcheck disable=SC2031
    printf '%s\n' "$TOKEN" > "$RALPH_CONFIG_DIR/oauth-token"
}

# ─── sandbox exec ───────────────────────────────────────────────────────────

@test "sandbox exec fails without a command" {
    setup_exec_mock
    run "$RALPH" sandbox exec
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"needs a command"* ]]
}

@test "sandbox exec starts the container, then runs ralph in it" {
    setup_exec_mock
    run "$RALPH" sandbox exec build -n 3
    [[ "$status" -eq 0 ]]
    grep -q '^up$' "$DEVCONTAINER_CALL_LOG"
    run ! grep -q '^zsh$' "$DEVCONTAINER_CALL_LOG"
    # docker exec ... <container> ralph build -n 3
    tr '\n' ' ' < "$DOCKER_CALL_LOG" | grep -q -- '-u node -w /workspace .*cid123 ralph build -n 3'
}

@test "sandbox exec passes the command's exit status on" {
    setup_exec_mock
    MOCK_DOCKER_EXEC_STATUS=7 run "$RALPH" sandbox exec build
    [[ "$status" -eq 7 ]]
}

@test "sandbox exec accepts --quiet for the command it runs" {
    setup_exec_mock
    run "$RALPH" sandbox exec build --quiet
    [[ "$status" -eq 0 ]]
    grep -q '^--quiet$' "$DOCKER_CALL_LOG"
}

@test "sandbox exec passes the plan token by name and not by value" {
    setup_exec_mock
    save_token
    run "$RALPH" sandbox exec build
    [[ "$status" -eq 0 ]]
    grep -q '^CLAUDE_CODE_OAUTH_TOKEN$' "$DOCKER_CALL_LOG"
    run ! grep -q "$TOKEN" "$DOCKER_CALL_LOG"
    grep -q "^CLAUDE_CODE_OAUTH_TOKEN=$TOKEN$" "$DOCKER_ENV_LOG"
}

@test "sandbox exec keeps every credential out of the devcontainer up arguments" {
    setup_exec_mock
    save_token
    MOCK_GH_AUTH_TOKEN="gho_secret123" run "$RALPH" sandbox exec build
    [[ "$status" -eq 0 ]]
    run ! grep -q "$TOKEN" "$DEVCONTAINER_CALL_LOG"
    run ! grep -q 'gho_secret123' "$DEVCONTAINER_CALL_LOG"
    run ! grep -q 'gho_secret123' "$DOCKER_CALL_LOG"
}

@test "sandbox exec leaves the API key out when a plan token is present" {
    setup_exec_mock
    save_token
    # shellcheck disable=SC2030,SC2031
    export ANTHROPIC_API_KEY="sk-ant-api-key"
    run "$RALPH" sandbox exec build
    [[ "$status" -eq 0 ]]
    run ! grep -q '^ANTHROPIC_API_KEY$' "$DOCKER_CALL_LOG"
}

@test "sandbox exec passes the API key when there is no plan token" {
    setup_exec_mock
    # shellcheck disable=SC2030,SC2031
    export ANTHROPIC_API_KEY="sk-ant-api-key"
    run "$RALPH" sandbox exec build
    [[ "$status" -eq 0 ]]
    grep -q '^ANTHROPIC_API_KEY$' "$DOCKER_CALL_LOG"
    run ! grep -q 'sk-ant-api-key' "$DOCKER_CALL_LOG"
}

@test "sandbox exec points git at the container's gh when a GitHub token exists" {
    setup_exec_mock
    MOCK_GH_AUTH_TOKEN="gho_secret123" run "$RALPH" sandbox exec build
    [[ "$status" -eq 0 ]]
    grep -q '^GH_TOKEN$' "$DOCKER_CALL_LOG"
    grep -q '^GIT_CONFIG_VALUE_1=!gh auth git-credential$' "$DOCKER_CALL_LOG"
}

@test "sandbox exec sets no git credential override without a GitHub token" {
    setup_exec_mock
    run "$RALPH" sandbox exec build
    [[ "$status" -eq 0 ]]
    run ! grep -q 'GIT_CONFIG_COUNT' "$DOCKER_CALL_LOG"
}

# ─── host guard ─────────────────────────────────────────────────────────────

@test "build started on the host runs in the sandbox" {
    setup_exec_mock
    unset RALPH_ALLOW_HOST
    run "$RALPH" build -n 2 --skip-push
    [[ "$status" -eq 0 ]]
    tr '\n' ' ' < "$DOCKER_CALL_LOG" | grep -q 'cid123 ralph build -n 2 --skip-push'
}

@test "each loop command is delegated from the host" {
    setup_exec_mock
    unset RALPH_ALLOW_HOST
    local c
    for c in plan review; do
        : > "$DOCKER_CALL_LOG"
        run "$RALPH" "$c"
        [[ "$status" -eq 0 ]]
        tr '\n' ' ' < "$DOCKER_CALL_LOG" | grep -q "cid123 ralph $c"
    done
}

@test "--host keeps a build on the host and is not passed on" {
    setup_exec_mock
    unset RALPH_ALLOW_HOST
    run "$RALPH" build --host
    [[ ! -e "$DOCKER_CALL_LOG" ]]
    [[ "$output" != *"unknown option"* ]]
}

@test "RALPH_ALLOW_HOST keeps a build on the host" {
    setup_exec_mock
    RALPH_ALLOW_HOST=1 run "$RALPH" build
    [[ ! -e "$DOCKER_CALL_LOG" ]]
}

@test "--dry-run never goes to the sandbox" {
    setup_exec_mock
    unset RALPH_ALLOW_HOST
    run "$RALPH" build --dry-run
    [[ ! -e "$DOCKER_CALL_LOG" ]]
}

@test "--help never goes to the sandbox" {
    setup_exec_mock
    unset RALPH_ALLOW_HOST
    run "$RALPH" build --help
    [[ "$status" -eq 0 ]]
    [[ ! -e "$DOCKER_CALL_LOG" ]]
}

@test "a command inside the container is not delegated again" {
    setup_exec_mock
    unset RALPH_ALLOW_HOST
    DEVCONTAINER=true run "$RALPH" build
    [[ ! -e "$DOCKER_CALL_LOG" ]]
}

@test "delegation reports a missing devcontainer CLI" {
    setup_exec_mock
    unset RALPH_ALLOW_HOST
    rm "$TEST_DIR/mock-bin/devcontainer"
    local filtered_path
    filtered_path=$(echo "$PATH" | tr ':' '\n' | while read -r dir; do
        [[ -x "$dir/devcontainer" ]] || printf '%s:' "$dir"
    done)
    PATH="${filtered_path%:}" run "$RALPH" build
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"'devcontainer' CLI not found"* ]]
}

# ─── sandbox token ──────────────────────────────────────────────────────────

@test "sandbox token saves a plan token with mode 600" {
    run bash -c "printf '%s\n' '$TOKEN' | '$RALPH' sandbox token"
    [[ "$status" -eq 0 ]]
    # shellcheck disable=SC2031
    [[ "$(tr -d '[:space:]' < "$RALPH_CONFIG_DIR/oauth-token")" == "$TOKEN" ]]
    local mode
    # shellcheck disable=SC2031
    mode=$(stat -f '%Lp' "$RALPH_CONFIG_DIR/oauth-token" 2>/dev/null || stat -c '%a' "$RALPH_CONFIG_DIR/oauth-token")
    [[ "$mode" == "600" ]]
}

@test "sandbox token accepts a token that wrapped over two lines" {
    local first="${TOKEN:0:60}" second="${TOKEN:60}"
    run bash -c "printf '%s\n%s\n' '$first' '$second' | '$RALPH' sandbox token"
    [[ "$status" -eq 0 ]]
    # shellcheck disable=SC2031
    [[ "$(tr -d '[:space:]' < "$RALPH_CONFIG_DIR/oauth-token")" == "$TOKEN" ]]
}

@test "sandbox token rejects text that is not a plan token" {
    run bash -c "printf '%s\n' 'pbpaste|tr-d' | '$RALPH' sandbox token"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not a Claude plan token"* ]]
    # shellcheck disable=SC2031
    [[ ! -e "$RALPH_CONFIG_DIR/oauth-token" ]]
}

@test "sandbox token rejects a token that was cut short" {
    run bash -c "printf '%s\n' 'sk-ant-oat01-abc' | '$RALPH' sandbox token"
    [[ "$status" -ne 0 ]]
    # shellcheck disable=SC2031
    [[ ! -e "$RALPH_CONFIG_DIR/oauth-token" ]]
}
