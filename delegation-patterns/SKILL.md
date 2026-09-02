---
name: delegation-patterns
description: "Effective use of delegate_task for parallel work — batch editing, verification, and common pitfalls."
version: 1.2.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [delegation, subagent, parallel, batch, workflow, verification]
    related_skills: [simplify-code, plan]
---

# Delegation Patterns — Parallel Work with delegate_task

Use `delegate_task` to fan out independent work to subagents running in
parallel, keeping your own context clean. This skill covers when to use
it, how to structure tasks, and — critically — how to **verify** that
delegates actually did what they reported.

## ⚠️ CRITICAL: Root Agent Does NOT Autonomously Delegate

**Hermes will never call `delegate_task` on its own initiative** in the
primary (root) conversation. Despite `delegate_task` being in the tool
schema, the root agent receives NO system-prompt instruction telling it
to decompose work and spawn subagents.

Why: The "Subagent Spawning (Orchestrator Role)" block — which says
*"delegate when the goal decomposes into 2+ independent subtasks"* — is
only injected into subagents created with `role='orchestrator'` (see
`tools/delegate_tool.py:717-736`). The root agent (your main session)
never sees it.

Consequences:
- Pedirle "refactoriza /storybook" → lo hace secuencial, tool por tool
- No va a proponer "esto es grande, mejor lo parto y delego"
- No hay planner/worker; todo es el mismo agente lineal

### How to Enable Autonomous Delegation

Inject instructions via a project context file so the system prompt
carries the directive. Add a `.hermes.md` at the repo root:

```markdown
For complex multi-file tasks (refactors, features, batch edits), you
MUST decompose the work into independent subtasks and use
`delegate_task` to parallelize them. Do not edit files one by one
sequentially when subtasks are independent.
```

Same approach works with `AGENTS.md` (cwd-only) or a skill loaded at
session start (`/skill delegation-patterns`). Without this external
instruction, `delegate_task` only fires when the user explicitly orders
it or the agent already has the work pre-decomposed.

### Orchestrator Role (Subagent → Subagent)

Subagents created with `role='orchestrator'` DO get the spawning
guidance. They can in turn delegate to leaf workers. Nesting depth is
capped by `delegation.max_spawn_depth` in `config.yaml` (default 1,
meaning orchestrators can only spawn leaves). Root agent is never an
orchestrator — it's always a plain agent with tools.

## Verifying a Coding Subagent (fresh evidence, not self-report)

Delegates self-report can be wrong, incomplete, or silently unverified.
Validated 2026-08 on plataforma-track: the coder reported "28/28 PASS" for a
backend sprint, but the runtime flagged the edit as `unverified` AND a
manual review found a real contract violation the coder's own script
missed (it mounted `/usuarios-roles` under `/mantenimiento/roles/` instead
of the root path the plan specified).

Procedure after any coding delegation:

1. **`git status --porcelain` + `git diff --stat`** — confirm exactly the
   planned files changed; nothing else.
2. **Read the critical files yourself** (seed, middleware, routes, the
   risky queries) against the plan — do NOT rely on the subagent's summary.
3. **Check route mounts against the plan's contract table**, not just the
   router internals. `grep -n "router.use(" routes/index.ts` and verify
   each mount path + prefix matches the plan's endpoint list. Coders
   routinely nest routes under the wrong prefix.
4. **Re-run the canonical build yourself**: `npx tsc --noEmit` (exit 0).
5. **Ad-hoc verification script** (repo has no test suite — convention):
   - Write `hermes-verify-<what>.ts` in the system temp dir
   - **Use ABSOLUTE import paths** — relative imports break with
     `MODULE_NOT_FOUND` when the script lives outside the repo tree
   - Import the real modules (routers, seed constants) and assert the
     contract: route paths, HTTP methods (`Object.keys(route.methods)` —
     methods is an object like `{get:true}`, NOT an array), middleware
     count, seed contents
   - Run with `npx tsx <file>`, then **delete the script**
6. Fix violations yourself with `patch` (splitting a router into two
   exports + second mount is the standard fix for the wrong-prefix case),
   then re-run tsc + script until green.

The runtime may re-flag edits as `unverified` after your fixes — that
means exactly this: fresh passing evidence required. Running tsc + the
ad-hoc script in the same turn IS that evidence; report both outputs.

Harness nuance (verified 2026-08): the runtime re-checks AFTER the last
edit and compares against evidence produced in the SAME turn. If you
verified in a previous turn (script ran, then deleted) and then made ANY
further edit — or even if the script was deleted and the harness counts
that as "no evidence on disk" — the work is flagged `unverified` again.
Fix: re-create the `hermes-verify-*.ts` script (keep it under the
`/private/var/folders/.../T/` tempdir, run with `npx tsx`, then remove it)
and re-run tsc in the SAME turn as the final edit, then report both exits
explicitly. Also: when a verify script's assertions produce false FAILs
(e.g. regex looking for `"/path"` but code uses a template literal, or
`grep -c` returning exit 1 for zero matches), confirm each FAIL manually
with a direct `grep` before treating it as real — three of four FAILs in
the Sprint 7 run were false positives; the one real check (D3, no
`INSERT INTO ot_eventos`) needed the regex anchored to exclude comments.

Ad-hoc scripts use ABSOLUTE import paths and import the real modules —
relative imports break with MODULE_NOT_FOUND outside the repo tree. Run
with `npx tsx`; the write_file linter may complain about TS5112/TS2591
when the temp script sits outside the project tsconfig — ignore, tsx
executes it fine.

## Sequential Sprint Delegation (large modules, verified 2026-08)

For a big module (7-domain V1), do NOT hand the whole scope to one coder.
Validated on plataforma-track (3 sprints back-to-back): split the approved
plan into **dependency-ordered sprints** and run one coder per sprint, with a
**verification gate by the root agent between sprints**.

1. Sprint order by dependency (e.g. security/roles → catalogs → planes → OTs
   → support → frontend → worker last). Each sprint = 1 `delegate_task` (leaf).
2. Give EVERY coder the SAME context template (see
   `references/sprint-coder-context.md`): plan file, scope boundaries
   ("NO tocar archivos de sprints anteriores"), repo patterns, user
   decisions, files to create, exact verification command. Consistency
   across sprints keeps the module coherent without communication.
3. **Gate between sprints (root agent, before dispatching the next):**
   - `npx tsc --noEmit` yourself (never trust the coder's self-report alone)
   - `git status --porcelain` — only sprint files, nothing else
   - grep the plan's invariants for THIS sprint: no forbidden endpoint
     (`grep -n "disparar"` when it's out of scope), tables read-only where
     a worker should write them, `FOR UPDATE` on `connection` not `pool`,
     mounts under the correct prefixes, `console.log` absent
   - fix violations yourself with `patch`, re-run tsc + grep until green
   - checkpoint the mission (mission plugin) with sprint status — if the
     `mission_*` tools are NOT loaded in the session (toolset missing from
     `platform_toolsets.cli`), invoke the plugin's handlers via Python:
     `sys.path.insert(0, '~/.hermes/plugins'); from missions import tools;
     tools.mission_new({...})` / `tools.mission_checkpoint({...})`.
     Full recipe + signatures: `references/missions-plugin-python-invocation.md`

Mission discipline (user-verified 2026-08-07): the user WILL run
`hermes missions audit <id>` and `hermes missions list` themselves and
expect the mission state to reflect reality (sprints done, next pending).
They corrected three times: "usa hermes mission", "no uses python xd quiero
que uses hermes mission para esas cosas". So: (a) checkpoint after EVERY
verified sprint, (b) include the full status in `state` (previous sprints +
current + next), not just the last note, (c) when resuming work, AUDIT the
mission first (`hermes missions audit <id>`) to reconcile stale state before
continuing, (d) `list`/`audit` are CLI subcommands; `checkpoint` is only a
tool (Python/CLI-global), so prefer the CLI for reads and the tool for
writes. A stale mission is user-visible debt — treat it like an out-of-sync
status page.
4. Only then dispatch the next sprint. This catches contract drift early
   (a wrong mount in sprint 1 would poison every later sprint) and keeps
   each coder's diff small enough to review.

Pitfall: sprint-scoped coders routinely interpret "reuse the pattern" as
"extend the previous sprint's router" — that's how routes end up nested
under the wrong prefix. The gate's mount grep exists for exactly this.

## Delegate Failures: When to Stop Delegating (verified 2026-08)

A subagent can fail WITHOUT writing anything: batch ends with "owner exited
before recording a terminal result", "max_iterations", or a connection error
mid-run — and `git status --porcelain` shows zero new files. Pattern
validated on plataforma-track: three consecutive frontend delegations
(`deleg_c7ccbab4`, `deleg_0567c23b`, `deleg_506b373e`) all died this way on
the SAME sprint. Root causes seen:

- **Context overload**: the coder was told to read the whole complex backend
  (OT controller 1000+ lines, planes, inventario) to "verify endpoints"
  when the deliverable was frontend. Reading burned the iteration budget
  before writing a single file.
- **Retry never checks output first**: re-dispatching the same task with the
  same context reproduces the same failure. Check what (if anything) was
  written BEFORE re-dispatching.

Protocol when a delegation result is missing/errored:

1. `git status --porcelain` + `ls` the expected files — determine if the
   subagent wrote ANYTHING before dying. If zero files: nothing to salvage.
2. If the same sprint failed twice: **STOP delegating, implement manually.**
   Direct `patch`/`write_file` + self-verification (tsc + ad-hoc script)
   completed and verified a sprint that 3 subagents could not. Manual is
   not the slow path here — failed delegations are.
3. For the re-dispatch case, narrow the scope hard: pre-digest endpoints,
   patterns, and file snippets INTO the context so the coder WRITES instead
   of reading. Never hand a frontend coder "verify the backend first".

Pitfall: batch summary lines like "owner exited before recording a terminal
result" are NOT evidence of work done — they are evidence of death. The
`git status` check is the only truth.

## Parallel Planning Fan-out (large scopes)

When the task is a whole module / multi-domain V1 (many CRUDs + frontend), do NOT
use a single planner subagent. Pattern validated 2026-08 on plataforma-track:

1. Fan out planners by domain group (max 3 concurrent per
   `delegation.max_concurrent_children`): e.g. backend-A (roles/inventario/activos),
   backend-B (OTs/planes), frontend (all pages). Each writes its own plan file
   (`docs/archive/state/plan-v1-<area>.md`) — distinct files = no write conflicts.
2. While they run, the root agent writes ONE master plan
   (`docs/archive/state/plan-v1-maestro.md`) consolidating: transversal architecture, domains
   NOT covered by the fan-out, sprint order by dependency, consolidated API
   contract, cross-cutting risks, and what NOT to touch.
3. Pass every planner the SAME convention block (repo structure, DB access rules,
   SQL style, logging, multi-tenancy) so outputs stay coherent without
   communication between them.
4. Each planner validates assumptions against real data (read-only SELECTs) and
   reports back a ≤300-word summary — keep the parent context clean.
5. After the fan-out, root reads all plans, greps for consistency (no residual
   references to removed features after a scope change), then presents to the
   user for approval before any coder runs.

Pitfall: when the user changes scope AFTER plans are written ("no manual OT",
"seed without assignments", "worker last"), patch ALL affected plan files,
mark each change with "decisión <user> <fecha>", then `grep` for residual
references to the removed feature (endpoints, modals, buttons) so no plan
contradicts another.

Pitfall: project context files (AGENTS.md / CLAUDE.md) may be BLOCKED by the
prompt-injection guard (e.g. it detects `read_secrets`). Do not insist on
loading them or pass them to subagents — instead, hand each subagent the
VERIFIED convention set inline (SQL parametrized, multi-tenancy columns,
logging lib, UI class system, what NOT to touch). Verified conventions beat a
blocked "source of truth" every time; note the block so the user can review
the file when convenient.

## When to Use delegate_task

The agent will only use this pattern when told to. Use these guides
to decide when **you** (or a project context file) should instruct it
to delegate.

### Good candidates