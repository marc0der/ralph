#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${RALPH_BIN_DIR:-$HOME/.local/bin}"
CONFIG_DIR="${RALPH_CONFIG_DIR:-$HOME/.config/ralph}"

echo "Installing ralph..."

mkdir -p "$BIN_DIR"
cp "$SCRIPT_DIR/ralph" "$BIN_DIR/ralph"
chmod +x "$BIN_DIR/ralph"
echo "  CLI:     $BIN_DIR/ralph"

mkdir -p "$CONFIG_DIR/prompts"
cp "$SCRIPT_DIR/prompts/plan.md" "$CONFIG_DIR/prompts/plan.md"
cp "$SCRIPT_DIR/prompts/build.md" "$CONFIG_DIR/prompts/build.md"
cp "$SCRIPT_DIR/prompts/review.md" "$CONFIG_DIR/prompts/review.md"
echo "  Prompts:    $CONFIG_DIR/prompts/"

mkdir -p "$CONFIG_DIR/templates"
cp "$SCRIPT_DIR/templates/PROGRESS.md" "$CONFIG_DIR/templates/PROGRESS.md"
cp "$SCRIPT_DIR/templates/IMPLEMENTATION_PLAN.md" "$CONFIG_DIR/templates/IMPLEMENTATION_PLAN.md"
echo "  Templates:  $CONFIG_DIR/templates/"

mkdir -p "$CONFIG_DIR/container"
cp "$SCRIPT_DIR/container/Dockerfile" "$CONFIG_DIR/container/Dockerfile"
cp "$SCRIPT_DIR/container/devcontainer.json" "$CONFIG_DIR/container/devcontainer.json"
echo "  Container:  $CONFIG_DIR/container/"

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo ""
    echo "Warning: $BIN_DIR is not in your PATH."
    echo "Add this to your shell profile:"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
fi

echo ""
echo "Done. Run 'ralph --help' to get started."
