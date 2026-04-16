# Makefile & Developer Experience

## Problem

Ralph is being shared with developers across multiple teams who need to be onboarded quickly. The current developer workflow has several friction points:

1. **No task runner** — developers must read README/CLAUDE.md to discover commands like `bats test/`, `shellcheck ralph`, etc.
2. **No prerequisite checker** — if something's missing, developers hit cryptic errors at runtime rather than a clear checklist up front.
3. **No automated dev setup** — installing prerequisites is manual, varies by platform (macOS vs Linux), and the README only documents some of them.
4. **Global installs pollute the host** — `devcontainer` CLI is currently expected to be installed globally (`npm install -g`), which can conflict with other projects or require elevated permissions.

## Goals

- A single entry point (`make help`) that shows developers everything they can do.
- `make doctor` to validate the environment and report what's missing.
- `make dev-setup` to install prerequisites on macOS and Linux.
- Project-local npm dependencies (specifically `@devcontainers/cli`) via `package.json` to avoid global installs where possible.
- Update the `ralph` script to resolve `devcontainer` from project-local `node_modules` or via `npx`, not just the global PATH.
- CI alignment so the pipeline uses the same Makefile targets developers use locally.

## Design decisions

### What goes project-local vs system-level

| Tool | Approach | Rationale |
|------|----------|-----------|
| `@devcontainers/cli` | Project-local via `package.json` devDependency | npm package, natural fit for local install; avoids global pollution |
| `bats` | System-level via brew/apt | No reliable npm package; lightweight test tool; already in `shell.nix` |
| `shellcheck` | System-level via brew/apt | Platform-specific binary; lightweight; already in `shell.nix` |
| `jq` | System-level via brew/apt | Common system utility, likely already installed |
| `git` | System-level (pre-existing) | Fundamental tool, not worth automating install |
| `docker` | System-level via brew/apt | System daemon, cannot be project-local |

### Devcontainer resolution in the ralph script

The `ralph` script currently does `command -v devcontainer` and fails if not found. This should be updated to a resolution chain:

1. `command -v devcontainer` (global — current behaviour, keeps backward compat)
2. `npx --yes devcontainer` (fallback — works if `@devcontainers/cli` is in any ancestor `node_modules` or the npm cache)

This means:
- Developers working on ralph itself get devcontainer from the local `node_modules` (after `npm install`)
- Users of ralph in other projects can install devcontainer however they like (global, project-local, or let `npx` fetch it)
- No breaking change to existing workflows

### Makefile design principles

- Every target has a `## description` comment for the self-documenting `help` target
- `make` with no arguments shows help (not a build — there's nothing to build)
- Targets use tools from PATH (system-level) or `node_modules/.bin/` (project-local)
- The `dev-setup` target detects the platform and uses the appropriate package manager
- The Makefile does not replace `install.sh` — that script installs ralph for _use_; the Makefile supports _development_ of ralph

## Implementation plan

### Phase 1: Makefile with core targets

Create a `Makefile` at the repo root with the following targets:

```
help          Show available targets (default)
test          Run all BATS tests
lint          Run ShellCheck on all scripts
check         Run lint + test (CI equivalent)
install       Install ralph via install.sh
uninstall     Remove ralph from ~/.local/bin and ~/.config/ralph
```

The `help` target uses the standard `grep -E` pattern to extract `##` comments. It is the default target (first in file, or `.DEFAULT_GOAL`).

The `test` target runs `bats test/`. The `lint` target runs `shellcheck` against the same file list as CI. The `check` target depends on both `lint` and `test`, in that order.

Files to change:
- Create `Makefile`

### Phase 2: `make doctor`

Add a `doctor` target that checks for all prerequisites and prints a checklist:

```
doctor        Check all prerequisites are installed
```

It should check: `git`, `docker`, `jq`, `node`/`npm`, `bats`, `shellcheck`, `claude` (optional), `codex` (optional), `devcontainer` (optional — will be project-local after phase 3).

For required tools, print a clear install instruction when missing. For optional tools, just note they're optional.

Also check:
- `~/.local/bin` is in PATH (for installed ralph)
- Docker daemon is running (not just installed)
- Node.js version is >= 20 (required by devcontainer Dockerfile)

Files to change:
- `Makefile` (add `doctor` target)

### Phase 3: `package.json` for project-local npm dependencies

Create a minimal `package.json` at the repo root:

```json
{
  "private": true,
  "description": "Development dependencies for ralph",
  "devDependencies": {
    "@devcontainers/cli": "^0.75.0"
  }
}
```

Mark `private: true` to prevent accidental publishing. No `name`, `version`, or `main` needed — this exists solely to manage dev dependencies.

Add `node_modules/` and `package-lock.json` handling:
- Add `node_modules/` to `.gitignore`
- Commit `package-lock.json` for reproducible installs

Files to change:
- Create `package.json`
- `.gitignore` (add `node_modules/`)

### Phase 4: `make dev-setup`

Add a `dev-setup` target that installs all development prerequisites:

```
dev-setup     Install development prerequisites (macOS & Linux)
```

Detection logic:
- macOS: use `brew` (check it's installed, error with install instructions if not)
- Linux: use `apt-get` (covers Ubuntu/Debian — the primary Linux targets for now)

Steps:
1. Detect platform via `uname -s`
2. Install system-level tools (`bats`, `shellcheck`, `jq`, `docker`) via the appropriate package manager — skip any already installed
3. Run `npm install` for project-local dependencies (devcontainer CLI)
4. Run `make doctor` at the end to confirm everything's green

Docker install note: on macOS, Docker Desktop is a `.dmg` / cask install. On Linux, `docker.io` or `docker-ce` via apt. The `dev-setup` target should handle both, but Docker often requires post-install steps (adding user to docker group on Linux, starting Docker Desktop on macOS). The target should print guidance for these manual steps rather than attempting to automate them.

Files to change:
- `Makefile` (add `dev-setup` target)

### Phase 5: Update ralph to resolve devcontainer locally

Update `cmd_sandbox()` in the `ralph` script to resolve the `devcontainer` CLI via a fallback chain rather than a hard `command -v` check.

Add a helper function `resolve_devcontainer()`:

```bash
resolve_devcontainer() {
    if command -v devcontainer >/dev/null 2>&1; then
        echo "devcontainer"
    elif npx --yes @devcontainers/cli --help >/dev/null 2>&1; then
        echo "npx @devcontainers/cli"
    else
        return 1
    fi
}
```

Then in `cmd_sandbox()`, replace the current `command -v devcontainer` check with a call to this helper. Store the resolved command and use it for both `devcontainer up` and `devcontainer exec` calls.

Note: `npx --yes` avoids the interactive "install this package?" prompt, which matters because ralph runs non-interactively in some contexts.

Files to change:
- `ralph` (update `cmd_sandbox()`, add `resolve_devcontainer()`)
- `test/sandbox.bats` (update tests to cover the resolution fallback)

### Phase 6: CI alignment

Update the GitHub Actions workflow to use `make check` instead of separate shellcheck and bats steps. This ensures CI runs the exact same commands developers run locally.

```yaml
jobs:
  check:
    name: Lint & Test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: make dev-setup
      - run: make check
```

This replaces the current two-job setup (separate `shellcheck` and `test` jobs) with a single job that mirrors the local workflow. The trade-off is slightly less granular CI feedback, but the benefit is exact parity between local and CI — "if `make check` passes locally, it passes in CI" becomes a reliable guarantee.

If separate job granularity is preferred, an alternative is to keep two jobs but have each call the Makefile:

```yaml
jobs:
  lint:
    ...
    steps:
      - uses: actions/checkout@v4
      - run: make lint
  test:
    ...
    steps:
      - uses: actions/checkout@v4
      - run: make test
```

Files to change:
- `.github/workflows/ci.yml`

### Phase 7: Update documentation

Update `README.md` and `CLAUDE.md` to reflect the new developer workflow:

**README.md** — update the Development section:
```markdown
## Development

Install development prerequisites:
    make dev-setup

Run the full check suite (lint + tests):
    make check

See all available targets:
    make help
```

Remove the `nix-shell` instructions (keep `shell.nix` as an alternative but don't document it as the primary path).

**CLAUDE.md** — update the Commands section to mention Makefile targets alongside the raw commands, so AI agents know to use them.

Files to change:
- `README.md`
- `CLAUDE.md`

## Out of scope (future work)

These ideas came up in discussion but are not included in this plan:

- **Shell completions** (`ralph --completions zsh/bash/fish`) — valuable for discoverability but a separate concern
- **`ralph doctor`** subcommand — similar to `make doctor` but built into the CLI for use inside the sandbox; worth doing once the Makefile version proves the concept
- **Versioned releases / one-liner install** — tagged releases and `curl | bash` installer for distribution to non-developers
- **`ralph self-update`** — pull latest and re-run install; depends on versioned releases
- **Homebrew tap** — macOS distribution channel; depends on versioned releases
