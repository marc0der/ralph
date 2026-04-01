# Multi-Backend Fixes

Corrective follow-up to the multi-backend spec. The codex backend was wired into the ralph script but the devcontainer sandbox doesn't have codex installed or its credentials mounted, the `RALPH_BACKEND` env var should be removed, and the README and CLAUDE.md are out of date.

## 1. Install Codex CLI in the Devcontainer

The Dockerfile already installs Claude Code via `npm install -g @anthropic-ai/claude-code`. Add the codex CLI the same way:

```dockerfile
npm install -g @openai/codex
```

This should be added alongside the existing Claude Code install line so both backends are available inside the sandbox.

## 2. Mount Codex Credentials into the Container

Codex stores its configuration and credentials in `~/.codex/` (overridable via `CODEX_HOME`). Key files include:

- `auth.json` — API key or ChatGPT OAuth tokens
- `config.toml` — model, permissions, MCP servers, sandbox mode, etc.

### Dynamic mount (cmd_sandbox)

Do **not** add a static mount in `devcontainer.json`. A static bind mount fails (or Docker auto-creates the directory as root) when `~/.codex` doesn't exist on the host. Instead, use the same optional-mount pattern already used for `~/.ssh` and `~/.config/gh` — only mount if the directory exists:

```bash
if [[ -d "$HOME/.codex" ]]; then
    mounts+=("type=bind,source=$HOME/.codex,target=/home/node/.codex")
fi
```

To mirror how `~/.claude` is handled, `cmd_sandbox` should also `mkdir -p "$HOME/.codex"` before `devcontainer up` so the mount is always present. This ensures codex can write credentials (e.g. after `codex login`) without the user having to create the directory manually.

Set `CODEX_HOME=/home/node/.codex` in the `containerEnv` section of `devcontainer.json`, mirroring `CLAUDE_CONFIG_DIR`.

### Environment variable forwarding

Codex also reads `OPENAI_API_KEY` from the environment as a fallback authentication method. Forward this env var into the container if it is set on the host, using the same `--remote-env` mechanism used for `SSH_AUTH_SOCK`:

```bash
if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    env_args+=("--remote-env" "OPENAI_API_KEY=$OPENAI_API_KEY")
fi
```

## 3. Remove `RALPH_BACKEND` Environment Variable

The multi-backend spec introduced `RALPH_BACKEND` as an env var for selecting the backend. Remove it. Backend selection should only be available via the `-b` / `--backend` CLI flag. Env vars for switching behaviour are not wanted.

This means:
- Remove the `RALPH_BACKEND` fallback from `resolve_backend` / `cmd_loop` in the ralph script
- Remove any tests that exercise `RALPH_BACKEND`
- Remove `RALPH_BACKEND` from usage text and the multi-backend spec's description
- Do **not** forward `RALPH_BACKEND` into the container

## 4. Update the README

The README has fallen behind the current state of ralph. The following sections need updates:

### Overview

The opening paragraph describes ralph as a Claude-specific tool. Update it to reflect that ralph supports multiple AI coding agent backends, not just Claude.

### Options table

Add the three missing flags:

| Flag | Description |
|------|-------------|
| `-b, --backend NAME` | Backend to use (claude, codex) — default: claude |
| `--skip-push` | Don't push after each iteration |
| `--dry-run` | Print what would be executed without running |

### Model selection

Document that the default model depends on the selected backend:

- `claude` backend: `opus`
- `codex` backend: `gpt-5.2-codex`

The `-m` flag overrides the default for whichever backend is active.

### Sandbox section

- Note that both Claude Code and Codex CLI are installed in the container
- Add `~/.codex` to the mounts list
- Mention `OPENAI_API_KEY` forwarding
- Replace the hardcoded `--dangerously-skip-permissions` reference with generic language — the permission flag is backend-specific

### Permissions & safety section

The current text hardcodes `--dangerously-skip-permissions`. Update to explain that each backend has its own permission-bypass flag and ralph applies the appropriate one automatically.

### Examples

Add examples showing backend selection:

```
ralph plan -b codex -g "design the auth module"
ralph build -b codex -n 10
ralph build --dry-run -b codex
```

### Project artifacts

The README's "Project artifacts" section only documents `CLAUDE.md`. Add `AGENTS.md` as the codex equivalent — codex projects use `AGENTS.md` for project instructions, and ralph's prompts already reference both files.

### Troubleshooting

Add a troubleshooting entry for codex CLI not found, parallel to the existing claude CLI entry.

## 5. Update CLAUDE.md

The project's `CLAUDE.md` still describes ralph as "an autonomous Claude Code loop runner" and only references `claude -p`. Update it to reflect multi-backend support:

- The "What is Ralph?" section should describe ralph as an autonomous AI coding agent loop runner, not Claude-specific
- The "Core loop flow" section references `claude` and `claude -p` — update to describe the generic backend command flow
- The "Shell scripting conventions" section should mention the `backend_<name>` function pattern used for backend definitions

## Testing

- Verify the container image builds successfully with both CLIs installed
- Verify `~/.codex` mount is skipped gracefully when the directory doesn't exist on the host
- Verify `OPENAI_API_KEY` is forwarded into the container when set
- Verify the script ignores `RALPH_BACKEND` env var (backend only selectable via `-b` flag)
- Backend tests updated to remove env var cases (`RALPH_BACKEND` selection, `-b` precedence over env var)
- Existing sandbox and dry-run tests continue to pass

## Out of Scope

- Changes to the ralph script's backend definitions (already implemented)
- Additional backends beyond Claude and Codex
- Codex OAuth browser flow inside the container (users should authenticate on the host first)
