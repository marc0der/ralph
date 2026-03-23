# Common test helper for ralph BATS tests
bats_require_minimum_version 1.5.0

# Path to the ralph script under test
export RALPH="$BATS_TEST_DIRNAME/../ralph"

# Create a temporary directory for each test with mock config
setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR" || return 1
    git init --quiet
    git commit --allow-empty -m "initial" --quiet

    # Set up mock ralph config dir
    export RALPH_CONFIG_DIR="$TEST_DIR/.ralph-config"
    mkdir -p "$RALPH_CONFIG_DIR/templates" "$RALPH_CONFIG_DIR/prompts"
    echo "# Progress" > "$RALPH_CONFIG_DIR/templates/PROGRESS.md"
    echo "# Plan prompt" > "$RALPH_CONFIG_DIR/prompts/plan.md"
    echo "# Build prompt" > "$RALPH_CONFIG_DIR/prompts/build.md"
}

# Clean up after each test
teardown() {
    rm -rf "$TEST_DIR"
}

# Helper: create a minimal .gitignore
create_gitignore() {
    printf "%s" "${1:-}" > .gitignore
}
