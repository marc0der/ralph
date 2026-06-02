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

@test "sandbox fails when workspace is a git submodule worktree" {
    command -v devcontainer >/dev/null 2>&1 || skip "devcontainer CLI not installed"
    # Simulate a submodule worktree: relocate the gitdir and replace .git
    # with a file containing a relative pointer (as `git submodule add` does).
    # The target must resolve so `git rev-parse --is-inside-work-tree` still
    # succeeds — that's the realistic scenario we want to reject. Keep the
    # relocated gitdir inside the temp workspace so teardown cleans it up;
    # writing outside TEST_DIR leaks state and makes the test flaky.
    mv .git submodule-gitdir
    echo "gitdir: submodule-gitdir" > .git
    run "$RALPH" sandbox
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"workspace is a git submodule"* ]]
}

@test "sandbox fails when config is missing" {
    command -v devcontainer >/dev/null 2>&1 || skip "devcontainer CLI not installed"
    # shellcheck disable=SC2030
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

@test "sandbox hashes workspace path with available md5 binary" {
    command -v md5sum >/dev/null 2>&1 || command -v md5 >/dev/null 2>&1 || skip "no md5sum or md5 available"
    command -v devcontainer >/dev/null 2>&1 || skip "devcontainer CLI not installed"
    # shellcheck disable=SC2031
    mkdir -p "$RALPH_CONFIG_DIR/container"
    # shellcheck disable=SC2031
    echo '{}' > "$RALPH_CONFIG_DIR/container/devcontainer.json"
    run "$RALPH" sandbox
    [[ "$output" != *"no md5sum or md5 command found"* ]]
}

# ─── env-var propagation tests ──────────────────────────────────────────────
# Creates a mock devcontainer that records its args to a log file and exits 0.
# Stubs ralph into PATH so cmd_sandbox's `command -v ralph` resolves correctly.
setup_sandbox_mock() {
    local mock_bin="$TEST_DIR/mock-bin"
    mkdir -p "$mock_bin"
    export DEVCONTAINER_CALL_LOG="$TEST_DIR/devcontainer.log"
    cat > "$mock_bin/devcontainer" << 'MOCKEOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$DEVCONTAINER_CALL_LOG"
printf -- '---\n' >> "$DEVCONTAINER_CALL_LOG"
# Validate --mount values like the real CLI: only type/source/target (and an
# optional external) keys are accepted. Catches unsupported keys (e.g. readonly)
# that the real devcontainer up would reject.
prev=""
for arg in "$@"; do
    if [[ "$prev" == "--mount" ]]; then
        IFS=',' read -ra parts <<< "$arg"
        for part in "${parts[@]}"; do
            case "${part%%=*}" in
                type|source|target|external) ;;
                *) echo "mock devcontainer: unsupported mount key in '$arg'" >&2; exit 2 ;;
            esac
        done
    fi
    prev="$arg"
done
exit 0
MOCKEOF
    chmod +x "$mock_bin/devcontainer"
    ln -s "$RALPH" "$mock_bin/ralph"
    # RALPH_CONFIG_DIR is exported in setup() (test_helper.bash); BATS runs
    # setup and the test body in the same subshell so the var is visible here.
    # shellcheck disable=SC2031
    mkdir -p "$RALPH_CONFIG_DIR/container"
    # shellcheck disable=SC2031
    echo '{}' > "$RALPH_CONFIG_DIR/container/devcontainer.json"
    export PATH="$mock_bin:$PATH"
    unset SSH_AUTH_SOCK
}

@test "sandbox propagates OPENROUTER_API_KEY when set" {
    setup_sandbox_mock
    unset OPENROUTER_API_KEY
    export OPENROUTER_API_KEY="or-key-123"
    run "$RALPH" sandbox
    [[ "$status" -eq 0 ]]
    grep -q "^OPENROUTER_API_KEY=or-key-123$" "$DEVCONTAINER_CALL_LOG"
}

@test "sandbox does not propagate OPENROUTER_API_KEY when unset" {
    setup_sandbox_mock
    unset OPENROUTER_API_KEY
    run "$RALPH" sandbox
    [[ "$status" -eq 0 ]]
    run ! grep -q "^OPENROUTER_API_KEY=" "$DEVCONTAINER_CALL_LOG"
}

@test "sandbox propagates ANTHROPIC_BASE_URL when set" {
    setup_sandbox_mock
    unset ANTHROPIC_BASE_URL
    export ANTHROPIC_BASE_URL="https://proxy.example.com"
    run "$RALPH" sandbox
    [[ "$status" -eq 0 ]]
    grep -q "^ANTHROPIC_BASE_URL=https://proxy.example.com$" "$DEVCONTAINER_CALL_LOG"
}

@test "sandbox propagates ANTHROPIC_AUTH_TOKEN when set" {
    setup_sandbox_mock
    unset ANTHROPIC_AUTH_TOKEN
    export ANTHROPIC_AUTH_TOKEN="bearer-token-abc"
    run "$RALPH" sandbox
    [[ "$status" -eq 0 ]]
    grep -q "^ANTHROPIC_AUTH_TOKEN=bearer-token-abc$" "$DEVCONTAINER_CALL_LOG"
}

@test "sandbox propagates ANTHROPIC_API_KEY when set" {
    setup_sandbox_mock
    unset ANTHROPIC_API_KEY
    # Per-test export is intentional — BATS isolates each test in a subshell.
    # shellcheck disable=SC2030
    export ANTHROPIC_API_KEY="sk-ant-key-123"
    run "$RALPH" sandbox
    [[ "$status" -eq 0 ]]
    grep -q "^ANTHROPIC_API_KEY=sk-ant-key-123$" "$DEVCONTAINER_CALL_LOG"
}

@test "sandbox propagates ANTHROPIC_API_KEY even when set to empty string" {
    setup_sandbox_mock
    unset ANTHROPIC_API_KEY
    # shellcheck disable=SC2031
    export ANTHROPIC_API_KEY=""
    run "$RALPH" sandbox
    [[ "$status" -eq 0 ]]
    grep -q "^ANTHROPIC_API_KEY=$" "$DEVCONTAINER_CALL_LOG"
}

@test "sandbox does not propagate ANTHROPIC_API_KEY when unset" {
    setup_sandbox_mock
    unset ANTHROPIC_API_KEY
    run "$RALPH" sandbox
    [[ "$status" -eq 0 ]]
    run ! grep -q "^ANTHROPIC_API_KEY=" "$DEVCONTAINER_CALL_LOG"
}

# ─── GPG agent forwarding tests ─────────────────────────────────────────────
# Installs a mock `gpgconf` into the sandbox mock-bin. With socket=yes it
# reports a real Unix socket (created via python3) and a homedir containing a
# pubring.kbx, exercising the forwarding path; with socket=no it reports a
# bogus (non-socket) path so the `-S` guard rejects forwarding.
setup_gpg_mock() {
    local want_socket="$1"
    local mock_bin="$TEST_DIR/mock-bin"
    local gpg_home="$TEST_DIR/gnupg"
    mkdir -p "$gpg_home"
    if [[ "$want_socket" == "yes" ]]; then
        command -v python3 >/dev/null 2>&1 || skip "python3 needed to create a test socket"
        python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' \
            "$gpg_home/S.gpg-agent" || skip "could not create test socket"
        [[ -S "$gpg_home/S.gpg-agent" ]] || skip "test socket was not created"
        echo "fake-keyring" > "$gpg_home/pubring.kbx"
    fi
    cat > "$mock_bin/gpgconf" << MOCKEOF
#!/usr/bin/env bash
# Only --list-dirs <name> is used by ralph.
case "\$2" in
    agent-extra-socket) echo "$gpg_home/nonexistent-extra" ;;
    agent-socket)       [[ "$want_socket" == "yes" ]] && echo "$gpg_home/S.gpg-agent" || echo "$gpg_home/missing" ;;
    homedir)            echo "$gpg_home" ;;
esac
MOCKEOF
    chmod +x "$mock_bin/gpgconf"
}

@test "sandbox forwards gpg agent socket and public keyring when available" {
    setup_sandbox_mock
    setup_gpg_mock yes
    run "$RALPH" sandbox
    [[ "$status" -eq 0 ]]
    grep -q "target=/home/node/.gnupg/S.gpg-agent$" "$DEVCONTAINER_CALL_LOG"
    grep -q "target=/home/node/.gnupg/pubring.kbx$" "$DEVCONTAINER_CALL_LOG"
}

@test "sandbox falls back from extra socket to standard agent socket" {
    setup_sandbox_mock
    setup_gpg_mock yes
    run "$RALPH" sandbox
    [[ "$status" -eq 0 ]]
    # The extra socket path is bogus, so forwarding must use the standard one.
    run ! grep -q "nonexistent-extra" "$DEVCONTAINER_CALL_LOG"
    grep -q "target=/home/node/.gnupg/S.gpg-agent$" "$DEVCONTAINER_CALL_LOG"
}

@test "sandbox does not forward gpg when no agent socket exists" {
    setup_sandbox_mock
    setup_gpg_mock no
    run "$RALPH" sandbox
    [[ "$status" -eq 0 ]]
    run ! grep -q "/home/node/.gnupg/" "$DEVCONTAINER_CALL_LOG"
}

@test "sandbox propagates GH_TOKEN when set" {
    setup_sandbox_mock
    unset GH_TOKEN
    export GH_TOKEN="gh-token-123"
    run "$RALPH" sandbox
    [[ "$status" -eq 0 ]]
    grep -q "^GH_TOKEN=gh-token-123$" "$DEVCONTAINER_CALL_LOG"
}

@test "sandbox does not propagate GH_TOKEN when unset" {
    setup_sandbox_mock
    unset GH_TOKEN
    run "$RALPH" sandbox
    [[ "$status" -eq 0 ]]
    run ! grep -q "^GH_TOKEN=" "$DEVCONTAINER_CALL_LOG"
}

@test "sandbox propagates GITHUB_TOKEN when set" {
    setup_sandbox_mock
    unset GITHUB_TOKEN
    export GITHUB_TOKEN="github-token-abc"
    run "$RALPH" sandbox
    [[ "$status" -eq 0 ]]
    grep -q "^GITHUB_TOKEN=github-token-abc$" "$DEVCONTAINER_CALL_LOG"
}

@test "sandbox does not propagate GITHUB_TOKEN when unset" {
    setup_sandbox_mock
    unset GITHUB_TOKEN
    run "$RALPH" sandbox
    [[ "$status" -eq 0 ]]
    run ! grep -q "^GITHUB_TOKEN=" "$DEVCONTAINER_CALL_LOG"
}

# ─── optional ~/.copilot mount tests ────────────────────────────────────────
# HOME is overridden to an isolated tmp dir so cmd_sandbox's `mkdir -p` runs
# against a path under our control and we can observe the conditional mount
# branch deterministically — without polluting the test runner's real $HOME.

@test "sandbox mounts ~/.copilot when host directory exists" {
    setup_sandbox_mock
    local fake_home="$TEST_DIR/fake-home"
    mkdir -p "$fake_home"
    HOME="$fake_home" run "$RALPH" sandbox
    [[ "$status" -eq 0 ]]
    grep -qF "type=bind,source=$fake_home/.copilot,target=/home/node/.copilot" "$DEVCONTAINER_CALL_LOG"
}

@test "sandbox skips ~/.copilot mount when host directory does not exist" {
    setup_sandbox_mock
    local fake_home="$TEST_DIR/fake-home"
    mkdir -p "$fake_home"
    # cmd_sandbox's unconditional `mkdir -p ~/.copilot` otherwise satisfies the
    # `[[ -d ~/.copilot ]]` check tautologically. Shadow mkdir in mock-bin to
    # filter out the .copilot arg so the conditional observes an absent dir;
    # remaining args are forwarded to the real mkdir found later in PATH.
    cat > "$TEST_DIR/mock-bin/mkdir" << 'MKDIREOF'
#!/usr/bin/env bash
args=()
for a in "$@"; do
    [[ "$a" == */.copilot ]] && continue
    args+=("$a")
done
[[ ${#args[@]} -eq 0 ]] && exit 0
PATH="${PATH#*:}" exec mkdir "${args[@]}"
MKDIREOF
    chmod +x "$TEST_DIR/mock-bin/mkdir"
    HOME="$fake_home" run "$RALPH" sandbox
    [[ "$status" -eq 0 ]]
    run ! grep -q "target=/home/node/.copilot" "$DEVCONTAINER_CALL_LOG"
}

@test "sandbox hash detection fails when no hashing command exists" {
    # Test the detection logic directly in a subshell with an empty PATH;
    # command is a bash builtin so it works even without PATH entries.
    run bash -c '
        PATH="/nonexistent"
        if command -v md5sum &>/dev/null; then
            echo "found md5sum"
        elif command -v md5 &>/dev/null; then
            echo "found md5"
        else
            echo "Error: no md5sum or md5 command found — install coreutils" >&2
            exit 1
        fi
    '
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"no md5sum or md5 command found"* ]]
}
