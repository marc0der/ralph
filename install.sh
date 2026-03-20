#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${RALPH_BIN_DIR:-$HOME/.local/bin}"
CONFIG_DIR="${RALPH_CONFIG_DIR:-$HOME/.config/ralph}"

echo "Installing ralph..."

# Install CLI
mkdir -p "$BIN_DIR"
cp "$SCRIPT_DIR/ralph" "$BIN_DIR/ralph"
chmod +x "$BIN_DIR/ralph"
echo "  CLI:     $BIN_DIR/ralph"

# Install default prompts
mkdir -p "$CONFIG_DIR/prompts"
cp "$SCRIPT_DIR/prompts/plan.md" "$CONFIG_DIR/prompts/plan.md"
cp "$SCRIPT_DIR/prompts/build.md" "$CONFIG_DIR/prompts/build.md"
echo "  Prompts: $CONFIG_DIR/prompts/"

# Check PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo ""
    echo "Warning: $BIN_DIR is not in your PATH."
    echo "Add this to your shell profile:"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
fi

echo ""
echo "Done. Run 'ralph --help' to get started."
