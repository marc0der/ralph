# The sandbox

`ralph sandbox` runs your project in a devcontainer built from `~/.config/ralph/container/`. The agent runs there as the non-root `node` user, with passwordless sudo, in "don't ask" mode. Your project is mounted at `/workspace`.

Each project gets its own container, reused between sessions. Shell history lives in a Docker volume, so it survives `sandbox clean` and `--rebuild`.

## Prerequisites

- **Docker**, rootful. Rootless Docker is not supported.
- **The devcontainer CLI**: `npm install -g @devcontainers/cli`.

## What's installed

Claude Code, the Codex CLI, the Copilot CLI, pi, Node.js 20, Bun, uv, SDKMAN, the Docker CLI, gh, git, zsh, jq and ripgrep.

SDKMAN comes without a JDK. If your project has a `.sdkmanrc`, run `sdk env install` inside the sandbox.

## What gets mounted

| Host                      | Container                        | Notes |
|---------------------------|----------------------------------|-------|
| `~/.claude`               | `/home/node/.claude`             | |
| `~/.claude/settings.json` | `/home/node/.claude/settings.json` | Read-only, so the agent can't change its own settings |
| `~/.codex`, `~/.copilot`, `~/.pi` | same paths under `/home/node` | Created on the host if missing |
| `~/.gitconfig`            | `/home/node/.gitconfig.host`     | Read-only, included by the container's own git config |
| `~/.ssh`                  | `/home/node/.ssh`                | If present |
| `~/.config/gh`            | `/home/node/.config/gh`          | If present |
| SSH agent socket          | `/tmp/ssh-agent.sock`            | If `SSH_AUTH_SOCK` is set |
| GPG agent socket          | `/home/node/.gnupg/S.gpg-agent`  | If `gpgconf` finds one; lets commits be signed with no private key in the container |
| `pubring.kbx`             | `/home/node/.gnupg/pubring.kbx`  | Alongside the GPG socket |
| Docker socket             | `/var/run/docker.sock`           | |
| `ralph` binary            | `/usr/local/bin/ralph`           | |
| `~/.config/ralph`         | `/home/node/.config/ralph`       | |
| Docker volume             | `/commandhistory`                | Shell history, one volume per project |

## What gets forwarded

These environment variables are passed into the container when set on the host: `OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `GEMINI_API_KEY`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`, `GH_TOKEN` and `GITHUB_TOKEN`.

If neither GitHub token is set, ralph asks `gh auth token` on the host. Modern `gh` keeps its token in the OS keyring, which the container can't reach through the `~/.config/gh` mount. If `gh` is installed but logged out, ralph warns you and starts the sandbox without GitHub authentication.

## SSH agent socket cannot be mounted

`ralph sandbox` can fail with an error like this:

```
invalid mount config for type "bind": stat /private/tmp/com.apple.launchd.XXXXXX/Listeners: operation not supported
```

Docker can't bind-mount your SSH agent socket. Either the socket sits outside the filesystem your Docker VM shares, or it's a launchd socket that doesn't survive the VM's file passthrough.

- **macOS with Colima, Rancher Desktop, OrbStack or another Lima-based runtime:** affected. The VM shares only `$HOME`, and macOS puts the agent socket under `/private/tmp`.
- **macOS with Docker Desktop:** usually fine. It provides its own SSH agent passthrough.
- **Linux:** not affected.

Start the sandbox without the agent socket:

```bash
SSH_AUTH_SOCK="" ralph sandbox
```

Git inside the container then falls back to the keys in the mounted `~/.ssh`, which works for keys without a passphrase.
