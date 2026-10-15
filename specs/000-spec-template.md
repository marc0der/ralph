---
id: "000"
created: 2026-10-15
area: []
---

# Spec Template

This file is a template, not a spec. It states no requirement. Copy it to
`specs/NNN-kebab-name.md`, where `NNN` is the next free number, and replace every section.

## Frontmatter

- `id` — the three-digit prefix of the file name, quoted.
- `created` — the date the spec is first committed, `YYYY-MM-DD`.
- `area` — one or more of `backend`, `sandbox`, `plan`, `build`, `review`, `auto`, `config`,
  `output`, `git`.
- `supersedes` — specs this one replaces whole.
- `amends` — specs this one overrides in part. The intro names the sections it replaces.
- `extends` — specs this one adds to without overriding any of it.
- `related` — specs that give context and that this one does not change.

The four relation keys list ids of earlier specs, quoted, such as `amends: ["014"]`. Leave out a
key that has no entries. A relation points backward only: never edit an earlier spec to record a
later one.

## Intro

One or two paragraphs above the first section. State the current behaviour and what this spec
changes. When the spec amends another, name it and the sections it replaces, for example:
"Corrective follow-up to `specs/014-spec-anchored-review.md`. This spec replaces sections 4 to 12."

## 1. Problem

What goes wrong today, with a reproduction or an example.

## 2. Rule

The decision, stated in a few lines.

## 3. Behaviour

What each affected command, prompt or file does under the rule. Use one subsection per command.

## 4. Documentation

The docs, prompts and guardrails files that change.

## 5. Testing

The tests that prove the rule, grouped by behaviour.

## 6. Accepted risks

What can still go wrong, and why that is accepted.

## 7. Out of scope

What this spec does not change.
