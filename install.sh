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
echo "  Prompts:    $CONFIG_DIR/prompts/"

# Install templates
mkdir -p "$CONFIG_DIR/templates"
cp "$SCRIPT_DIR/templates/PROGRESS.md" "$CONFIG_DIR/templates/PROGRESS.md"
cp "$SCRIPT_DIR/templates/IMPLEMENTATION_PLAN.md" "$CONFIG_DIR/templates/IMPLEMENTATION_PLAN.md"
echo "  Templates:  $CONFIG_DIR/templates/"

# Install container config
mkdir -p "$CONFIG_DIR/container"
cp "$SCRIPT_DIR/container/Dockerfile" "$CONFIG_DIR/container/Dockerfile"
cp "$SCRIPT_DIR/container/devcontainer.json" "$CONFIG_DIR/container/devcontainer.json"
echo "  Container:  $CONFIG_DIR/container/"

# Check PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    shell_name="$(basename "${SHELL:-}")"
    case "$shell_name" in
        zsh)
            rc_file="$HOME/.zshrc"
            export_line="export PATH=\"$BIN_DIR:\$PATH\""
            ;;
        bash)
            if [[ "$(uname -s)" == "Darwin" ]]; then
                rc_file="$HOME/.bash_profile"
            else
                rc_file="$HOME/.bashrc"
            fi
            export_line="export PATH=\"$BIN_DIR:\$PATH\""
            ;;
        fish)
            rc_file="$HOME/.config/fish/config.fish"
            export_line="fish_add_path $BIN_DIR"
            ;;
        *)
            rc_file=""
            export_line="export PATH=\"$BIN_DIR:\$PATH\""
            ;;
    esac

    echo ""
    echo "Warning: $BIN_DIR is not in your PATH."
    if [[ -n "$rc_file" ]]; then
        echo "Detected shell: $shell_name"
        echo ""
        echo "Add this line to $rc_file:"
        echo "  $export_line"
        echo ""
        echo "Or run this one-liner to do it now:"
        echo "  echo '$export_line' >> $rc_file"
        echo ""
        echo "Then restart your shell or run: source $rc_file"
    else
        echo "Add this to your shell profile:"
        echo "  $export_line"
    fi
fi

echo ""
echo "Done. Run 'ralph --help' to get started."
