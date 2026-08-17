# Implementation Plan

**Prioritised list of work items. Order is priority — the build agent picks the top incomplete item.**

## Entry Format

This file holds three sections: this title, `## Entry Format`, and `## Items`. Never add another heading.

Each entry uses these six fields, in this order, and no others:

- [ ] **Short imperative title**
  Spec: `specs/file.md` item N
  Scope: What is included. What is excluded.
  Files: `path/to/file`, `path/to/other`
  Steps:
  1. Imperative technical instruction.
  2. Imperative technical instruction.
  Done when: Criterion the agent can check without a human.

Rules:

- The spec states what to build. The item states how to build it.
- Write at most 150 words and 14 lines per item. Write at most 10 words per title.
- Write at most 2 sentences for `Scope`. Write at most 2 sentences for `Done when`.
- Write at most 8 steps. Write one action per step. Write at most 20 words per step.
- Split any item that needs a ninth step. That item is too large for one iteration.
- Name symbols, option paths, literal values, and files to copy an idiom from.
- Never cite line numbers. Never paste code. Every named token must be greppable.
- Write every field in Simplified Technical English. Use active voice and present tense.
- Record no rationale, no evidence, no history, and no status. `PROGRESS.md` holds those.

Markers:

- `- [ ]` open
- `- [x]` shipped
- `- [~]` superseded or blocked; its replacement is appended to the end of the list

## Items
