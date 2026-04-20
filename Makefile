.DEFAULT_GOAL := help

SHELL_SCRIPTS := ralph install.sh
TEST_SCRIPTS  := test/*.bats test/test_helper.bash

.PHONY: help test lint check install uninstall doctor dev-setup

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*##"}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

test: ## Run all BATS tests
	bats test/

lint: ## Run ShellCheck on all scripts
	shellcheck $(SHELL_SCRIPTS)
	shellcheck $(TEST_SCRIPTS)

check: lint test ## Run lint + tests (CI equivalent)

doctor: ## Check all prerequisites are installed
	@echo "Checking prerequisites..."
	@echo ""
	@echo "Required:"
	@command -v git >/dev/null 2>&1 \
		&& printf "  \033[32m✓\033[0m git\n" \
		|| printf "  \033[31m✗\033[0m git — install from https://git-scm.com\n"
	@command -v docker >/dev/null 2>&1 \
		&& printf "  \033[32m✓\033[0m docker\n" \
		|| printf "  \033[31m✗\033[0m docker — install from https://docs.docker.com/get-docker/\n"
	@command -v docker >/dev/null 2>&1 \
		&& docker info >/dev/null 2>&1 \
		&& printf "  \033[32m✓\033[0m docker daemon running\n" \
		|| printf "  \033[33m!\033[0m docker daemon not running — start Docker Desktop or dockerd\n"
	@command -v jq >/dev/null 2>&1 \
		&& printf "  \033[32m✓\033[0m jq\n" \
		|| printf "  \033[31m✗\033[0m jq — brew install jq / sudo apt-get install jq\n"
	@command -v node >/dev/null 2>&1 \
		&& printf "  \033[32m✓\033[0m node ($$(node --version))\n" \
		|| printf "  \033[31m✗\033[0m node — install from https://nodejs.org (v20+)\n"
	@command -v npm >/dev/null 2>&1 \
		&& printf "  \033[32m✓\033[0m npm\n" \
		|| printf "  \033[31m✗\033[0m npm — ships with node\n"
	@echo ""
	@echo "Development:"
	@command -v bats >/dev/null 2>&1 \
		&& printf "  \033[32m✓\033[0m bats\n" \
		|| printf "  \033[31m✗\033[0m bats — brew install bats-core / sudo apt-get install bats\n"
	@command -v shellcheck >/dev/null 2>&1 \
		&& printf "  \033[32m✓\033[0m shellcheck\n" \
		|| printf "  \033[31m✗\033[0m shellcheck — brew install shellcheck / sudo apt-get install shellcheck\n"
	@echo ""
	@echo "Optional (backends):"
	@command -v claude >/dev/null 2>&1 \
		&& printf "  \033[32m✓\033[0m claude\n" \
		|| printf "  \033[33m-\033[0m claude — npm install -g @anthropic-ai/claude-code\n"
	@command -v codex >/dev/null 2>&1 \
		&& printf "  \033[32m✓\033[0m codex\n" \
		|| printf "  \033[33m-\033[0m codex — npm install -g @openai/codex\n"
	@echo ""
	@echo "Sandbox:"
	@(command -v devcontainer >/dev/null 2>&1 || test -x node_modules/.bin/devcontainer) \
		&& printf "  \033[32m✓\033[0m devcontainer\n" \
		|| printf "  \033[31m✗\033[0m devcontainer — run 'npm install' or 'make dev-setup'\n"
	@echo ""
	@echo "Environment:"
	@echo "$$PATH" | tr ':' '\n' | grep -q "$$HOME/.local/bin" \
		&& printf "  \033[32m✓\033[0m ~/.local/bin is in PATH\n" \
		|| printf "  \033[33m!\033[0m ~/.local/bin is not in PATH — add: export PATH=\"$$HOME/.local/bin:\$$PATH\"\n"

dev-setup: ## Install development prerequisites (macOS & Linux)
	@echo "Installing development prerequisites..."
	@OS=$$(uname -s); \
	if [ "$$OS" = "Darwin" ]; then \
		if ! command -v brew >/dev/null 2>&1; then \
			echo "Error: Homebrew is required on macOS. Install from https://brew.sh"; \
			exit 1; \
		fi; \
		echo "Detected macOS — using Homebrew"; \
		for pkg in bats-core shellcheck jq; do \
			if brew list $$pkg >/dev/null 2>&1; then \
				echo "  ✓ $$pkg (already installed)"; \
			else \
				echo "  Installing $$pkg..."; \
				brew install $$pkg; \
			fi; \
		done; \
		if ! command -v docker >/dev/null 2>&1; then \
			echo ""; \
			echo "  Docker is not installed."; \
			echo "  Install Docker Desktop from https://docs.docker.com/desktop/install/mac-install/"; \
			echo "  Or: brew install --cask docker"; \
		else \
			echo "  ✓ docker (already installed)"; \
		fi; \
	elif [ "$$OS" = "Linux" ]; then \
		if ! command -v apt-get >/dev/null 2>&1; then \
			echo "Error: apt-get not found. Only Debian/Ubuntu are supported by dev-setup."; \
			exit 1; \
		fi; \
		echo "Detected Linux — using apt-get"; \
		NEEDED=""; \
		for pkg in bats shellcheck jq; do \
			if command -v $$pkg >/dev/null 2>&1; then \
				echo "  ✓ $$pkg (already installed)"; \
			else \
				NEEDED="$$NEEDED $$pkg"; \
			fi; \
		done; \
		if [ -n "$$NEEDED" ]; then \
			echo "  Installing:$$NEEDED"; \
			sudo apt-get update -qq && sudo apt-get install -y -qq $$NEEDED; \
		fi; \
		if ! command -v docker >/dev/null 2>&1; then \
			echo ""; \
			echo "  Docker is not installed."; \
			echo "  Install with: sudo apt-get install docker.io"; \
			echo "  Then:         sudo usermod -aG docker $$USER"; \
			echo "  (Log out and back in for group change to take effect)"; \
		else \
			echo "  ✓ docker (already installed)"; \
		fi; \
	else \
		echo "Error: unsupported platform '$$OS'. Only macOS and Linux are supported."; \
		exit 1; \
	fi
	@echo ""
	@echo "Installing project-local npm dependencies..."
	npm install
	@echo ""
	@echo "Done. Running doctor to verify:"
	@echo ""
	@$(MAKE) --no-print-directory doctor

install: ## Install ralph via install.sh
	./install.sh

uninstall: ## Remove ralph from ~/.local/bin and ~/.config/ralph
	rm -f "$$HOME/.local/bin/ralph"
	rm -rf "$$HOME/.config/ralph"
	@echo "Uninstalled ralph."
