# AI_RULES.md

## Project Overview

This project is a Godot 4.6.2 implementation heavily inspired by Heroes of Might and Magic III.

The goal is NOT to invent new mechanics unless explicitly requested.

When implementing gameplay systems, prioritize compatibility with HoMM3 behavior and data structures over creative alternatives.

Before implementing any gameplay-related feature, consult:

* HoMM3_Clone_DesignDocument.md
* HoMM3_Research_GameMechanics.md

These documents are the primary source of truth.

If implementation details conflict with assumptions, trust the documentation rather than model knowledge.

---

## General Development Rules

Always:

* Read relevant project files before making changes.
* Prefer modifying existing systems over creating parallel systems.
* Keep solutions simple and maintainable.
* Avoid speculative architecture.
* Avoid unnecessary abstractions.
* Avoid premature optimization.

When requirements are unclear:

* Ask for clarification.
* Do not invent game mechanics.

---

## Godot Version

Target engine:

Godot 4.6.2

Requirements:

* Use Godot 4 APIs only.
* Never use Godot 3 syntax.
* Use typed GDScript whenever possible.
* Use @export instead of legacy export syntax.
* Use @onready when appropriate.
* Use class_name for reusable classes.
* Use signal declarations with typed arguments.

---

## Code Style

Use:

* One primary class per file.
* Strong typing whenever practical.
* Clear and descriptive variable names.
* Small focused methods.
* Explicit return types.

Avoid:

* Single-letter variable names.
* Deep nesting.
* Massive scripts.
* Unused code.
* Dead code.
* Commented-out code.

Code should be self-explanatory.

Comments should explain WHY, not WHAT.

All comments must be written in English.

---

## Architecture Rules

Prefer composition over inheritance.

Avoid inheritance chains deeper than:

BaseClass -> ChildClass

Use reusable components when appropriate.

Favor event-driven communication through signals.

Avoid tight coupling between systems.

Game systems should communicate through:

* signals
* interfaces
* managers
* event dispatchers

Avoid direct cross-references whenever possible.

---

## Scene Structure

Keep scenes focused.

A scene should represent a single responsibility.

Examples:

* AdventureMap
* Hero
* Town
* UnitStack
* CombatArena
* InventoryPanel

Avoid giant scenes that manage unrelated systems.

---

## Autoload Rules

Autoloads are allowed only for true global systems.

Examples:

* GameState
* SaveSystem
* AudioManager
* LocalizationManager

Do not create new autoloads without justification.

Prefer dependency injection where practical.

---

## Data-Driven Design

Prefer data-driven solutions.

Gameplay values should not be hardcoded when they can be stored in:

* Resources
* Configuration files
* Databases
* Game data assets

Examples:

* creatures
* spells
* artifacts
* buildings
* factions
* terrain

Data should be editable without changing gameplay code.

---

## HoMM3 Compatibility Rules

When implementing Heroes III mechanics:

Priorities:

1. Match original gameplay behavior.
2. Match original formulas.
3. Match original turn order.
4. Match original movement logic.
5. Match original combat rules.

Do not simplify mechanics unless explicitly requested.

If exact behavior is unknown:

* Search existing project documentation.
* Mark assumptions clearly.
* Keep implementation extensible.

---

## UI Rules

Separate:

* game logic
* presentation
* input handling

UI should not contain gameplay logic.

UI should consume data from gameplay systems.

Avoid business logic inside Control nodes.

---

## Performance Rules

Prefer readable code first.

Optimize only when:

* profiling identifies a bottleneck
* the user explicitly requests optimization

Avoid micro-optimizations.

---

## Refactoring Rules

Before refactoring:

* Understand current behavior.
* Preserve functionality.
* Preserve save compatibility when applicable.

Do not perform large architectural rewrites unless requested.

Prefer incremental improvements.

---

## File Modification Rules

When changing files:

* Modify the minimum number of files required.
* Reuse existing code when possible.
* Avoid duplicate implementations.
* Search for existing solutions before creating new ones.

---

## Testing Rules

For gameplay changes:

* Consider edge cases.
* Consider AI interactions.
* Consider save/load compatibility.
* Consider multiplayer implications if applicable.

Always think through failure scenarios.

---

## Working Process

For significant tasks:

1. Analyze existing implementation.
2. Read related documentation.
3. Create a brief implementation plan.
4. Implement.
5. Verify consistency.
6. Summarize changes.

Do not immediately start coding without understanding the surrounding system.

---

## Response Format

For non-trivial requests:

First provide:

* findings
* relevant files
* implementation plan

Then implement.

Avoid making hidden assumptions.

Explain important design decisions.

---

## Golden Rule

Maintain consistency with the project's architecture and Heroes III design goals.

Consistency is more important than cleverness.
