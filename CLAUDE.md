# CLAUDE.md

## Project Context

This project is a Godot 4.6.2 game heavily inspired by Heroes of Might and Magic III.

Before implementing any gameplay feature, system, mechanic, UI element, or refactor, read the relevant project documentation.

Mandatory documents:

1. AI_RULES.md
2. HoMM3_Clone_DesignDocument.md
3. HoMM3_Research_GameMechanics.md

These documents are the source of truth.

Do not rely on model memory of Heroes III when project documentation provides guidance.

---

## Required Workflow

For any non-trivial task:

1. Inspect relevant existing code.
2. Read relevant documentation.
3. Identify affected files.
4. Create a short implementation plan.
5. Implement changes.
6. Verify consistency with project architecture.
7. Summarize modifications.

Do not start coding immediately without understanding the existing system.

---

## Development Priorities

Priority order:

1. Correctness
2. HoMM3 compatibility
3. Maintainability
4. Readability
5. Performance

Avoid unnecessary complexity.

Prefer extending existing systems over creating new parallel systems.

---

## Godot Requirements

* Target Godot 4.6.2
* Use typed GDScript
* Use Godot 4 APIs only
* Follow AI_RULES.md coding standards
* Keep gameplay logic data-driven when practical

---

## Heroes III Compatibility

When implementing game mechanics:

* Prefer original Heroes III behavior.
* Follow documented formulas and mechanics.
* Do not simplify mechanics unless explicitly requested.
* Clearly identify assumptions when documentation is incomplete.

Consistency with the original design is more important than introducing new ideas.

---

## Refactoring Policy

Do not perform large architectural rewrites unless explicitly requested.

Prefer small, safe, incremental improvements.

Preserve existing behavior unless the task explicitly requires behavior changes.

---

## Response Expectations

Before implementing significant changes, provide:

* Relevant files
* Findings
* Implementation plan

Then proceed with implementation.

Always explain important design decisions.
