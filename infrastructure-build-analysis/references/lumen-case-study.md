# Lumen Case Study

## Discovery Context

During a feasibility assessment of replacing Membrane's QuickJS-WASM with a custom Rust JS engine, the user pointed to `lucid-softworks/lumen` as a counterexample to the claim that building a JS engine from scratch takes months/years even with AI.

## Project Summary

| Attribute | Value |
|-----------|-------|
| Repo | `github.com/lucid-softworks/lumen` |
| License | MIT |
| Language | Rust (std-only, zero dependencies) |
| Started | June 28, 2026 |
| Assessed | July 7, 2026 (~10 days old) |
| Commits | 1,017 |
| Authors | ImLunaHey (human) + claude (Claude AI) |
| test262 | 53,400/53,400 (100% including annexB, intl402, staging) |
| Stars | 171 (at assessment time) |

## Architecture

```
lumen (engine crate — 50+ source files, zero deps)
├── lexer       — tokenizer
├── parser      — builds AST
├── interpreter — tree-walking (bytecode tier in development)
├── value       — RC<RefCell<Object>> object model
├── builtins    — globalThis, Object, Array, Function, Math, errors
├── regex       — full RegExp with \p{…}, backreferences
├── coroutine   — stackful coroutines for generators + async/await
├── modules     — ES modules (top-level await, import defer)
├── intl        — Intl support
├── temporal    — Temporal API
├── snapshot    — AST precompile/decode codec
└── host        — OpState, ResourceTable, embed API

lumen-host     — Extension system, ThreadPool, CallbackQueue
lumen-runtime  — Event loop, console, process
lumen-timers   — setTimeout/setInterval/queueMicrotask
lumen-fs       — sync + async filesystem
lumen-web      — WinterTC APIs (fetch, URL, crypto, EventTarget)
lumen-node     — Node compatibility (require, node:path/os/fs, N-API)
lumen-repl     — Interactive shell
lumen-cli      — CLI entry point
lumen-wasm     — WASM compilation target
```

## Embed API (relevant for Membrane integration)

```rust
// Create engine with fresh realm
let mut engine = Engine::new();

// Define native functions accessible from JS
engine.define_global("myFunc", 1, |ctx, args| {
    let state = ctx.op_state();  // typed host state
    // ...
    Value::undefined()
});

// Evaluate JS
match engine.eval("myFunc(42)", false)? {
    Completion::Value(v) => println!("{}", v),
    Completion::Throw { name, message } => eprintln!("{name}: {message}"),
}
```

## Key Takeaways for Membrane

1. **The engine IS buildable with AI.** Lumen proves that a single person + Claude can produce a 100% test262-compliant JS engine in ~10 days.

2. **Fork > build from scratch.** Lumen is MIT, zero-deps, and has the embed API Membrane needs. The bespoke Membrane layer (host objects, gref bridge, snapshot/fork, debugger) is the same work regardless of engine choice.

3. **The embed API is crucial.** Lumen's `OpState` + `NativeFn` pattern is exactly what Membrane needs — typed host state that native functions can access, with property interception for host objects.

4. **WASM target exists.** Lumen has `lumen-wasm` crate, so the current worker→wasmtime→WASM architecture could be preserved during migration.

5. **Active development velocity is extreme.** 1,017 commits in 10 days, with features landing hourly. The project trajectory suggests it'll have bytecode compilation and JIT within weeks/months.
