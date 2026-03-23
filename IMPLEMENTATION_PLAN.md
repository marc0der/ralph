# Ralph Improvement Plan

## 1. Bug Fixes (Critical)

- [x] **Fix `.gitignore` newline handling** (`ralph:134`) — Before appending entries, ensure the file ends with a newline to prevent concatenation with the last existing line. Add: `[[ -s .gitignore && $(tail -c1 .gitignore) != "" ]] && echo >> .gitignore`
- [ ] **Validate `-n` iterations as positive integer** (`ralph:198`) — After parsing, check `[[ "$max_iterations" =~ ^[1-9][0-9]*$ ]]` and exit with a clear error if invalid.
- [ ] **Improve git push error handling** (`ralph:256-259`) — Distinguish between "no upstream" (where `-u` is the right fix) and other failures (network, rejected). Only fall back to `-u` when the error message indicates no upstream tracking branch.

## 2. Input Validation & Safety

- [ ] **Check `claude` CLI is in PATH** — Before entering the loop in `cmd_loop()`, verify `command -v claude >/dev/null` and exit with a helpful message if missing.
- [ ] **Check `git` is available and we're in a repo** — Before `git branch --show-current`, verify we're inside a git working tree with `git rev-parse --is-inside-work-tree`.
- [ ] **Add signal trap for clean exit** — Register `trap cleanup SIGINT SIGTERM` at the top of `cmd_loop()` that logs the current iteration number and state to stderr so users know where it stopped.

## 3. README Improvements

- [ ] **Clarify `CLAUDE.md` is user-maintained** — The artifacts table mentions it but could confuse users into thinking `ralph init` creates it. Add a sentence after the table: *"Note: `CLAUDE.md` is your project's own configuration file for Claude Code — ralph reads it but never creates or modifies it."*
- [ ] **Expand devcontainer section** — Explain *why* `--dangerously-skip-permissions` is acceptable (container network isolation, ephemeral environment) and note that outside containers, Claude will prompt for approval on tool calls.
- [ ] **Add troubleshooting section** covering:
  - `claude` CLI not installed
  - `ralph` not in PATH after install
  - Push rejected / diverged branch
  - Resuming after a failed iteration (just re-run `ralph build`)
- [ ] **Add recovery/resumption guidance** — Explain that re-running `ralph build` picks up from `IMPLEMENTATION_PLAN.md` state, so no special recovery step is needed.
- [ ] **Add model selection guidance** — Brief note on when to use `opus` (complex reasoning, architecture) vs `sonnet` (faster, cheaper, straightforward tasks).

## 4. Test Suite

- [ ] **Add BATS test framework** — Create `test/` directory with BATS as the test runner. Add a `test/test_helper.bash` with common setup (temp dirs, mock fixtures).
- [ ] **Test `cmd_init`** — Verify it creates `PROGRESS.md`, `IMPLEMENTATION_PLAN.md`, `specs/`, updates `.gitignore`, and respects `--prompts` flag. Test idempotency (running init twice doesn't duplicate).
- [ ] **Test `cmd_clean`** — Verify it deletes artifacts that exist and handles the case where none exist.
- [ ] **Test `cmd_archive`** — Verify artifacts move to `.ralph/<timestamp>/`, directory is created, and handles "nothing to archive" case.
- [ ] **Test `resolve_prompt`** — Verify priority order: local `PROMPT_<mode>.md` > installed default > error with helpful message.
- [ ] **Test `.gitignore` handling** — Verify entries are appended correctly, no duplicates, newline edge case is handled.
- [ ] **Test input validation** — Verify non-integer iterations, missing claude CLI, and running outside a git repo all produce clear errors.

## 5. CI/CD

- [ ] **Add GitHub Actions workflow** — `.github/workflows/ci.yml` that runs ShellCheck on `ralph` and `install.sh`, and runs the BATS test suite on push/PR.
- [ ] **Add ShellCheck configuration** — `.shellcheckrc` with any necessary directives. Fix any ShellCheck findings in `ralph` and `install.sh`.

## 6. Nice-to-Have Enhancements

- [ ] **Add `--skip-push` flag** — Allow running build loops without pushing after each iteration (useful for local testing/experimentation).
- [ ] **Add `--dry-run` flag** — Print what would be executed without actually invoking `claude` or `git push`.
- [ ] **Add `.gitignore` to the ralph repo itself** — The repo doesn't have one; add a minimal one for common OS/editor artifacts.
