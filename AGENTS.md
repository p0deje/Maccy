# Agent Operating Guide

## Baseline

- Baseline commit before the roadmap work: `6528bd8ad18a39f44fd03128f3384b708f580b85`.
- Roadmap source of truth: `docs/audit/2026-06-14/roadmap/`.
- High-level audit summary: `docs/audit/2026-06-14/09-roadmap.md`.

## Objective

From this baseline forward, execute the roadmap in `docs/audit/2026-06-14/roadmap/` carefully, incrementally, and completely. Do not skip any listed big step, small step, test, verification gate, acceptance criterion, complexity budget, pipeline budget, or I/O limit.

Follow the roadmap order unless a documented dependency requires otherwise:

1. `step-0-safety.md`
2. `step-1-concurrency-scaffolding.md`
3. `step-2-ingest-to-actor.md`
4. `step-3-image-pipeline.md`
5. `step-4-data-pipeline.md`
6. `step-5-text-search.md`
7. `step-6-memory.md`
8. `step-7-swift6.md`
9. `step-8-cpp.md`

Read these roadmap references before implementing each affected area:

- `A-architecture-target.md`
- `B-test-strategy.md`
- `C-complexity-and-limits.md`

## Execution Rules

- Work one small roadmap task at a time.
- Use TDD for behavior changes: write or update the focused failing test first, then implement the minimum correct production change, then run the focused test.
- Add meaningful tests for every fix or refactor unless the roadmap explicitly says the step is configuration-only.
- Keep edits scoped to the current roadmap task and its tests.
- Preserve user or agent work already present in the worktree. Do not delete or revert unrelated changes.
- Prefer existing project patterns, APIs, and style over new abstractions.
- Do not change user-visible behavior unless the roadmap explicitly requires it.
- Record any unavoidable deviation from the roadmap in the relevant audit or progress document before committing.

## Commit And Push Discipline

- Commit after every completed small step.
- A small-step commit must include the test and implementation for that step when applicable.
- A small-step commit message should name the roadmap item, for example: `fix(bs0.1): guard first item navigation`.
- Push only after a completed big step passes its required build and test gates.
- Do not push a partial big step unless explicitly instructed by the user.

## Verification Gates

At each small step:

- Run the narrowest useful test or build command that proves the step.
- Confirm the changed behavior against the roadmap acceptance text.
- Update the corresponding checklist item only when evidence proves it is done.

At each big step boundary:

- Run the roadmap-required build and test commands.
- Confirm no checklist item in that big step remains incomplete.
- Confirm complexity, pipeline, and I/O constraints still match the roadmap.
- Commit the completed big step if the roadmap asks for a roll-up commit, then push.

## Current First Target

Begin with BS-0 in `docs/audit/2026-06-14/roadmap/step-0-safety.md`, starting at:

- `0.1` fix `Collection+Surrounding.item(before:)` first-index trap.
- `0.2` add the regression test.

