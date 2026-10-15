# GitHub Token Keyring Forwarding

The `gh` CLI fails inside the sandbox with a stale/invalid token error, even though `gh auth status` on the host reports a healthy login (e.g. `Logged in to github.com account marc0der (keyring)`). The regression was introduced by `gh`'s migration to OS-keyring token storage: ralph propagates GitHub auth into the container by bind-mounting `~/.config/gh`, but the token no longer lives in that directory — it lives in the host keyring, which is not reachable from inside the container.

## Problem

Ralph makes the host's GitHub auth available to the container two ways, both in `cmd_sandbox`:

1. **Bind mount** (`ralph:357-358`) — `~/.config/gh` is mounted read-write into the container when it exists on the host:

   ```bash
   if [[ -d "$HOME/.config/gh" ]]; then
       mounts+=("type=bind,source=$HOME/.config/gh,target=/home/node/.config/gh")
   fi
   ```

2. **Env forwarding** (`ralph:414-419`) — `GH_TOKEN` and `GITHUB_TOKEN` are forwarded as `--remote-env` when set on the host:

   ```bash
   if [[ -n "${GH_TOKEN:-}" ]]; then
       ssh_env+=("--remote-env" "GH_TOKEN=$GH_TOKEN")
   fi
   if [[ -n "${GITHUB_TOKEN:-}" ]]; then
       ssh_env+=("--remote-env" "GITHUB_TOKEN=$GITHUB_TOKEN")
   fi
   ```

Historically the bind mount was sufficient: `gh` stored the OAuth token inline in `~/.config/gh/hosts.yml`, so mounting the directory carried the token into the container. Modern `gh` (secure storage) moved the token into the OS keyring, leaving `hosts.yml` with only non-secret fields:

```yaml
github.com:
    git_protocol: ssh
    users:
        marc0der: {}
    user: marc0der          # username only — no oauth_token
```

Inside the container, `gh` reads the mounted `hosts.yml`, sees a configured user for `github.com`, but has no token — the keyring that holds it is a host OS service with no presence in the container. The result is the stale/invalid-token failure. The host keeps working because it reads the keyring directly.

The env-forwarding path does not save the situation either: the user authenticated via `gh auth login` (keyring), so `GH_TOKEN` and `GITHUB_TOKEN` are unset in the host shell, and ralph forwards nothing.

This was not caught earlier because the failure only manifests after a host-side `gh` keyring migration; a host that still carries an inline token in `hosts.yml`, or that exports `GH_TOKEN`/`GITHUB_TOKEN`, continues to work.

## Fix

At sandbox-launch time, derive the live token from the host keyring via `gh auth token` and forward it into the container as `GH_TOKEN`. Because `GH_TOKEN` has the highest precedence in `gh`, it overrides the tokenless mounted `hosts.yml` and resolves both the "no token" and "stale token" cases with one mechanism.

### Derivation

In `cmd_sandbox`, immediately before the existing `GH_TOKEN` forwarding block (`ralph:414`), derive the token as a **fallback** — only when no token is already present in the environment:

```bash
# Derive a GitHub token from the host keyring when none is exported. gh's
# secure storage keeps the token in the OS keyring, which the container cannot
# reach via the ~/.config/gh bind mount; `gh auth token` reads it on the host so
# it can be forwarded as an env var (highest precedence in gh) below.
if [[ -z "${GH_TOKEN:-}" && -z "${GITHUB_TOKEN:-}" ]] && command -v gh >/dev/null 2>&1; then
    gh_token="$(gh auth token 2>/dev/null)" || true
    if [[ -n "$gh_token" ]]; then
        GH_TOKEN="$gh_token"
    else
        echo "Warning: gh is installed but no GitHub token is available (run 'gh auth login'" >&2
        echo "on the host). The sandbox will start without GitHub CLI authentication." >&2
    fi
fi
```

The existing `GH_TOKEN` forwarding block (`ralph:414-416`) then picks up the derived value with no further change — there is exactly one place that emits `--remote-env GH_TOKEN`.

### Precedence

Token selection is a strict fallback chain; an explicitly exported variable is always a deliberate signal and wins:

1. `GH_TOKEN` set in the host shell → forwarded as-is (existing behaviour; lets a PAT override for CI/testing).
2. else `GITHUB_TOKEN` set → forwarded as-is (existing behaviour).
3. else `gh` installed and `gh auth token` returns non-empty → forwarded as `GH_TOKEN`.
4. else nothing forwarded (and, when `gh` is installed, a warning is emitted — see below).

The derivation never overrides an explicit `GH_TOKEN`/`GITHUB_TOKEN`. The live keyring token is used only to fill the gap those variables would otherwise leave.

### Failure handling

The derivation is best-effort and must never abort the sandbox:

- Only `gh auth token`'s stdout is captured; stderr is discarded with `2>/dev/null` (covers logged-out, locked/unavailable keyring, and headless-session cases).
- A non-zero exit is tolerated (`|| true`) and the empty-stdout guard prevents forwarding `GH_TOKEN=` or an error string.
- `gh auth token` returns the active account's token; `--hostname` is not needed for the github.com-only case.

### Warning

When `gh` is installed, both env vars are empty, and `gh auth token` yields nothing (logged out or keyring unreachable), emit a loud, actionable warning to **stderr**, and continue launching the sandbox:

```
Warning: gh is installed but no GitHub token is available (run 'gh auth login'
on the host). The sandbox will start without GitHub CLI authentication.
```

The warning fires **only** when `gh` is present. A host with no `gh` installed is a legitimate "does not use GitHub CLI" setup and must stay silent.

### Scope

The derivation, forwarding, and warning all live in `cmd_sandbox`, which runs once per `ralph sandbox` invocation. The `plan`/`build` loops (`cmd_loop`) are designed to run *inside* the container and inherit `GH_TOKEN` from the container environment, so they need no changes and the warning is emitted at most once per sandbox entry — never per loop iteration.

### Mount is retained, not mutated

The `~/.config/gh` bind mount (`ralph:357-358`) stays as-is — it still carries the username, `git_protocol`, and other non-secret config, and continues to work for hosts that keep an inline token. Ralph must **not** clean or rewrite the container's `hosts.yml`: because the directory is bind-mounted, that file *is the host's live config*, and the env-var override already shadows its (absent) token. The stale-token state can only resurface when the host is logged out, which the warning already surfaces.

## Documentation

### README

`README.md:112` currently documents both the `~/.config/gh` mount and `GH_TOKEN`/`GITHUB_TOKEN` forwarding. Update it to note that when neither variable is set, ralph derives the token from `gh auth token` so keyring-stored `gh auth login` sessions propagate into the container, and that a warning is printed when `gh` is installed but logged out.

### AGENTS.md / CLAUDE.md

Update any parallel description of sandbox auth forwarding to mention the `gh auth token` fallback. No other changes are expected; the existing sandbox flow already covers the mechanism.

## Testing

The behaviour is non-deterministic with respect to the test host's `gh` state: on any machine where `gh` is installed and logged in, the previously passing `sandbox does not propagate GH_TOKEN when unset` test would now derive a real token and forward it. Tests must therefore control `gh` on `PATH` rather than depend on the host.

### Harness change

Extend `setup_sandbox_mock` (`test/sandbox.bats`) to install a `gh` stub into the existing `mock_bin` (already first on `PATH`), driven by an env var so each test can simulate logged-in or logged-out:

```bash
cat > "$mock_bin/gh" << 'MOCKEOF'
#!/usr/bin/env bash
[[ "$1 $2" == "auth token" ]] || exit 0
if [[ -n "${MOCK_GH_AUTH_TOKEN:-}" ]]; then
    printf '%s\n' "$MOCK_GH_AUTH_TOKEN"
    exit 0
fi
echo "not logged into any GitHub hosts" >&2
exit 1
MOCKEOF
chmod +x "$mock_bin/gh"
```

The stub only intercepts `gh auth token`; it is inert for any other invocation and only matters when `GH_TOKEN`/`GITHUB_TOKEN` are unset.

### New tests

- **Derives GH_TOKEN from `gh auth token`**: `GH_TOKEN`/`GITHUB_TOKEN` unset, `MOCK_GH_AUTH_TOKEN=derived-xyz` → assert `^GH_TOKEN=derived-xyz$` is forwarded to the mock devcontainer.
- **Explicit GH_TOKEN wins over derivation**: `GH_TOKEN=explicit-123` set, `MOCK_GH_AUTH_TOKEN=derived-xyz` set → assert the forwarded value is `explicit-123`, not the derived token.
- **GITHUB_TOKEN suppresses derivation**: `GITHUB_TOKEN=gh-abc` set, `MOCK_GH_AUTH_TOKEN=derived-xyz` set → assert `GITHUB_TOKEN=gh-abc` is forwarded and no derived `GH_TOKEN` line appears.
- **Warns when gh present but logged out**: `GH_TOKEN`/`GITHUB_TOKEN` unset, `MOCK_GH_AUTH_TOKEN` unset (stub exits non-zero) → assert the warning text appears on stderr and the sandbox still exits 0.

### Existing tests

- **`sandbox does not propagate GH_TOKEN when unset`** is reworked: leave `MOCK_GH_AUTH_TOKEN` unset so the stub acts logged-out, then assert both that no `GH_TOKEN` line is forwarded **and** that the loud warning is emitted. This keeps the assertion a true negative regardless of the test host's real `gh` login.
- All other sandbox tests continue to pass; the `gh` stub is inert unless `gh auth token` is invoked with the env vars unset.

## Out of Scope

- Mounting or syncing the host OS keyring into the container.
- Rewriting, cleaning, or otherwise mutating the container/host `~/.config/gh/hosts.yml`.
- GitHub Enterprise Server / multi-host token selection (`gh auth token --hostname ...`).
- Token refresh or rotation during a long-lived sandbox session (the token is captured once at launch).
- Changes to the `plan`/`build` loops or any backend definition.
- Changes to the `~/.config/gh` mount condition itself.
