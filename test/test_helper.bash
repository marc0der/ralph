# Common test helper for ralph BATS tests
bats_require_minimum_version 1.5.0

# Path to the ralph script under test
export RALPH="$BATS_TEST_DIRNAME/../ralph"

# Tests assert ralph's host-side behaviour (e.g. the outside-container warning).
# When tests run inside the devcontainer DEVCONTAINER=true leaks in and silently
# flips that branch — unset it so every test sees the same host-side defaults.
unset DEVCONTAINER

# Create a temporary directory for each test with mock config
setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR" || return 1
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test"
    git commit --allow-empty -m "initial" --quiet

    # Set up mock ralph config dir
    export RALPH_CONFIG_DIR="$TEST_DIR/.ralph-config"
    mkdir -p "$RALPH_CONFIG_DIR/templates" "$RALPH_CONFIG_DIR/prompts" "$RALPH_CONFIG_DIR/skills/commit"
    echo "# Progress" > "$RALPH_CONFIG_DIR/templates/PROGRESS.md"
    # Use the real plan template, not a stub: it carries the '## Items' heading
    # and a column-zero exemplar entry, and item counting depends on both.
    cp "$BATS_TEST_DIRNAME/../templates/IMPLEMENTATION_PLAN.md" \
        "$RALPH_CONFIG_DIR/templates/IMPLEMENTATION_PLAN.md"
    echo "# Plan prompt" > "$RALPH_CONFIG_DIR/prompts/plan.md"
    echo "# Build prompt" > "$RALPH_CONFIG_DIR/prompts/build.md"
    echo "# commit skill" > "$RALPH_CONFIG_DIR/skills/commit/SKILL.md"
}

# Clean up after each test
teardown() {
    rm -rf "$TEST_DIR"
}

# Helper: create a minimal .gitignore
create_gitignore() {
    printf "%s" "${1:-}" > .gitignore
}

# Helper: mock claude that streams JSONL events with controllable timing and
# exit code. The delays and the sentinel are what make live rendering
# observable: with MOCK_DELAY set the mock does not finish until well after its
# first event, and it announces its own finish by creating $MOCK_SENTINEL, so a
# test can prove a rendered line arrived before the backend exited.
# Knobs (all read at run time, so one mock serves every test):
#   MOCK_DELAY    seconds to sleep between events (default 0)
#   MOCK_SENTINEL path to touch just before exiting (default: none)
#   MOCK_EXIT     exit code (default 0)
create_streaming_backend() {
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
# Snapshot $TMPDIR from inside the iteration: the per-run stream file only
# exists while the backend runs, so a test cannot see it after the EXIT trap.
[[ -n "${MOCK_TMP_LISTING:-}" ]] && ls -A "${TMPDIR:-/tmp}" > "$MOCK_TMP_LISTING"
echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls -la"}}]}}'
sleep "${MOCK_DELAY:-0}"
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"done here"}]}}'
sleep "${MOCK_DELAY:-0}"
# `result` carries the text too: the claude summary filter reads `.result`, so
# a result event without it renders a bare empty line on the non-verbose path.
echo '{"type":"result","subtype":"success","duration_ms":1234,"duration_api_ms":1000,"num_turns":3,"result":"done here","session_id":"s1","total_cost_usd":0.02,"usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50}}'
[[ -n "${MOCK_SENTINEL:-}" ]] && : > "$MOCK_SENTINEL"
exit "${MOCK_EXIT:-0}"
MOCK
    chmod +x "$TEST_DIR/bin/claude"
}
