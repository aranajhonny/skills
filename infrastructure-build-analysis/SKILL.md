---
name: infrastructure-build-analysis
description: Evaluate build-vs-adopt decisions for custom infrastructure, accounting for AI-augmented development feasibility.
triggers:
  - "should we build X from scratch"
  - "how hard would it be to build a custom engine"
  - "build vs buy"
  - "replace X with custom Rust implementation"
  - "can AI build this"
---

# Infrastructure Build-vs-Adopt Analysis

Use this skill when evaluating whether to build custom infrastructure from scratch or adopt/fork an existing solution. The calculus has fundamentally shifted with modern AI coding tools (Claude 4+, Opus, etc.).

## Core Principle

**Before declaring something infeasible or estimating multi-year efforts, check whether AI-assisted projects have already solved similar problems.** The difference between a human-only estimate and an AI-augmented one can be 50-100x.

## Assessment Framework

### Step 1: Scan for AI-assisted precedents
Search GitHub for projects that:
- Are built with the target language (e.g., Rust)
- List "Claude", "AI-assisted", or have co-authors like `claude` or `github-actions[bot]` committing alongside human authors
- Are MIT/Apache licensed (forkable)
- Pass standard compliance suites (test262 for JS engines, etc.)

### Step 2: Distinguish engine from integration
When replacing a core component (like a JS engine), separate the analysis:
- **The generic part** (JS engine, HTTP parser, etc.): Often already solved by AI-assisted projects
- **The bespoke integration layer** (host objects, schema bridge, debugger): This is ALWAYS the bulk of the work regardless of engine choice

### Step 3: Estimate in AI-augmented terms
For a project of the user's scale, estimate:
- Fork + adapt existing: Days to weeks
- Build from scratch with AI: Weeks to months (was 6-18 months pre-AI)
- Human-only from scratch: Still months to years

## Key Reference: Lumen (JS Engine)

`lucid-softworks/lumen` — MIT-licensed, zero-dependency Rust JS engine:
- Built in ~10 days (June 28 – July 7, 2026), 1,017 commits
- By 1 human (Luna) + Claude AI
- 53,400/53,400 test262 pass (100%)
- Features: generators, async/await, ES modules, Proxy/Reflect, Intl, Temporal, RegExp, typed arrays, BigInt, SharedArrayBuffer
- Compiles to WASM
- Has embed API (`Engine`, `NativeFn`, `OpState`, `ResourceTable`)
- Has runtime: event loop, fs, fetch, HTTP server, Node compat
- Active development (commits every few hours)

See `references/lumen-case-study.md` for detailed analysis.

## Pitfalls

- **Don't make absolute feasibility claims without checking AI-assisted precedents.** "Impossible in days" was wrong for JS engines — Lumen proves otherwise.
- **Don't estimate in pre-AI terms.** A 6-month human project can be a 2-week AI-augmented project.
- **The integration layer dwarfs the engine.** For Membrane, the JS engine itself is ~20% of the work; the host object system, gref bridge, snapshot/fork, and debugger are the real scope.
- **When user challenges your estimate with a counterexample, investigate it immediately.** Don't defend — verify.

## Output Format

When answering "how hard would X be?", structure the response as:
1. What the current system actually does (not what you assume it does)
2. What exists that could replace it (forkable projects, AI-assisted precedents)
3. Concrete estimate breakdown (not a single number — decompose by subsystem)
4. Recommended approach with time estimate
