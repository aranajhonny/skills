---
name: architect
description: "Use when designing a non-trivial module, API, or subsystem before writing code. Sketch the caller's usage and types first, screen the shape against design red flags, and ship a one-page rationale alongside the type sketch."
---

# Architect

Design before implementing. Sketch the caller's usage and the type shapes first, then fill in code against the sketch. If implementation proves the sketch wrong, throw it out and redesign.

## Workflow

1. **Ground.** Build a mental model of every system the new code touches. Read the relevant code and trace the data flow. Naming a file isn't grounding. Skip only for greenfield work with nothing to integrate against.

2. **Sketch, caller first.** Write the caller's usage first — the README or quickstart they'll read, plus two or three realistic call sites. Then derive the type sketch, signatures, and module map from it. The usage is the spec; when they diverge, reconcile the sketch to the usage.

3. **Design it twice.** Produce at least two structurally distinct candidates before committing, even when the first looks sufficient. Whole-shape alternatives, not point fixes inside one shape.

4. **Screen against red flags.** Reject or revise shallow modules, information leakage, temporal decomposition, and pass-through methods. See `references/design-red-flags.md`.

5. **Pick on interface depth.** Prefer the design that hides more complexity behind a smaller public surface. A rich interface concentrates capability instead of scattering it across layers.

6. **Write the rationale.** Ship `references/rationale-template.md` alongside the sketch: problem, usage, shape, tradeoffs, alternatives considered, open questions.

## Implement against the sketch

Replace `not implemented` bodies with code. The sketch is the contract. Deviations are signal worth surfacing, not friction to absorb silently: if a function needs a parameter the sketch didn't anticipate, ask whether the sketch was wrong or the implementation is overreaching.

## Scrap when the architecture is wrong

If implementation keeps producing friction the sketch can't absorb, throw the sketch out. The signal is a *pattern*, not single instances:

- The same workaround appearing repeatedly across unrelated code.
- Multiple unrelated edge cases that all need special-case branches.
- Types that need escape hatches (`any`, casts, optional fields always set in practice).
- The "we need a lock" reflex when the sketch said the state wasn't shared.
- Callers having to know the abstraction's internal rules to use it.

When you scrap, redesign as if the new constraints were day-one assumptions, and subtract before adding: the new sketch should be smaller before it grows.
