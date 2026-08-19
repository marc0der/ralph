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
    # For tests that manipulate the PATH
    ORIGINAL_PATH="$PATH"
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
    echo "# Review prompt" > "$RALPH_CONFIG_DIR/prompts/review.md"
    echo "# commit skill" > "$RALPH_CONFIG_DIR/skills/commit/SKILL.md"
}

# Clean up after each test
teardown() {
    PATH="$ORIGINAL_PATH"
    rm -rf "$TEST_DIR"
}

# Helper: create a minimal .gitignore
create_gitignore() {
    printf "%s" "${1:-}" > .gitignore
}
