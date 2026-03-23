# Common test helper for ralph BATS tests

# Path to the ralph script under test
RALPH="$BATS_TEST_DIRNAME/../ralph"

# Create a temporary directory for each test
setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    git init --quiet
    git commit --allow-empty -m "initial" --quiet
}

# Clean up after each test
teardown() {
    rm -rf "$TEST_DIR"
}

# Helper: create a minimal .gitignore
create_gitignore() {
    printf "%s" "${1:-}" > .gitignore
}
