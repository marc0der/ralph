---
id: "020"
created: 2026-10-15
area: [config]
amends: ["019"]
---

# Config Template Location

The shipped config file lives at the repository root as `config.yaml`. In a checkout of Ralph
that is also a Ralph workspace, the root file reads as "this workspace's config", but Ralph never
reads it there: a run reads `./ralph.yaml`, else `$CONFIG_DIR/config.yaml`. An operator who tunes a
dogfood run by editing the root file changes the product, and commits that change with their
work. This spec moves the template out of the root and gives this repository the same local
config any other workspace gets.

## 1. Template location

- The shipped config file moves from `config.yaml` to `templates/config.yaml`, beside the artifact
  templates that `ralph init` scaffolds. `ralph init --config` still copies the central copy,
  which `install.sh` writes from this file.
- The repository root holds no `config.yaml`.
- The file content does not change.

## 2. Installation

- `install.sh` copies `templates/config.yaml` to `$CONFIG_DIR/config.yaml`, overwriting the old
  copy on every install. The installed path does not change.
- `install.sh` does not copy `config.yaml` into `$CONFIG_DIR/templates/`.
- `resolve_config`, `ralph init --config` and the sandbox mounts do not change.

## 3. Dogfooding

- Add `ralph.yaml` to this repository's `.gitignore`, in the Ralph artifacts block. It is the
  entry `ralph init` adds to every workspace, so `ralph init` here leaves `.gitignore` unchanged.
  An operator dogfooding Ralph runs `ralph init --config` and tunes `./ralph.yaml`, which git
  ignores.
- An operator with local edits to the old root `config.yaml` moves them into `./ralph.yaml`
  (`ralph init --config`, then re-apply the edits) and discards them from the tracked file
  before pulling.

## 4. Documentation

- `CLAUDE.md` and `AGENTS.md`: the `~/.config/ralph/config.yaml` entry in the installation layout
  ends with `, copied from templates/config.yaml`.
- `specs/019-phase-config.md` is a chronological record and does not change.

## Testing

- The tests that read the shipped file read `templates/config.yaml`: the install test compares it
  with `$CONFIG_DIR/config.yaml`, and the shipped-file tests copy it as the central copy.
- A test asserts the repository root holds no `config.yaml`.
- A test asserts `install.sh` writes no `$CONFIG_DIR/templates/config.yaml`.
- A test asserts the repository's `.gitignore` holds every entry `ralph init` adds, so
  `ralph init` in this checkout prints no `Added to .gitignore:` line.

## Out of Scope

- Moving the installed `$CONFIG_DIR/config.yaml`.
- Renaming `ralph.yaml` or changing config resolution.
- Any change to the config file's keys or comments.
