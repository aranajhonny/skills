---
name: feature-workflow
description: "End-to-end workflow for implementing features: requirements gathering -> confirmation -> plan -> implement -> verify. Prevents the 'start coding before user finishes explaining' antipattern."
version: 1.0.0
author: Hermes Agent (learned from Jhonny)
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [workflow, requirements, implementation, feature]
    related_skills: [plan, systematic-debugging, test-driven-development]
---

# Feature Workflow

Use this skill when the user describes a new feature or change request — whether it's a ticket, a verbal description, or a screenshot with instructions.

The core problem this solves: **jumping to code before the full requirement is understood** wastes time and frustrates the user ("undo everything, you didn't ask me anything").

## Mandatory flow

### Phase 1: Listen completely

**Do NOT start coding, planning, or proposing solutions while the user is still explaining.**

- Let them finish the entire description
- Do NOT interject with "I'll do X" or "Y already exists"
- Do NOT reach for tools yet
- If they paste a ticket or link, read it fully before responding

### Phase 2: Confirm understanding

Once they're done, summarize what you understood:

```
What I understood:
1. [point A]
2. [point B]
3. [point C]

Am I on track?
```

Key questions to ask (pick what's relevant):
- "Does this replace something existing or run in parallel?"
- "Which parts of the current system should I NOT touch?"
- "What level does it apply to? (individual asset, asset type, organization, global)"
- "Who will see/use this? Are there visibility restrictions?"

**Do NOT ask open-ended "what should I do?"** — propose a direction and ask for confirmation instead.

### Phase 3: Name things correctly

If the user used specific terms ("asset type", "levels", "templates"), use those exact terms in the UI. If the internal DB/model name differs from the user-facing name, translate in the UI layer, not the other way around.

**Bad:** Showing "Asset Category" in the UI when the user said "Asset Type"
**Good:** Keep `categorias_activo` in the code/DB, show "Asset Type" in labels

### Phase 4: Consider data visibility

Always ask yourself: **what data should this user actually see?**

- If showing configurations, filter by the user's organization
- Don't show system defaults / base templates unless the user needs to see them
- Don't show configurations from other organizations
- If the feature is about personalization, show ONLY personalizations — not the full catalog with fallbacks

### Phase 4.5: Diagnose-before-redesign (when user shows confusion about existing UI)

When the user pastes a screenshot, share of data, or says a page is "overloaded" / "nothing makes sense":

1. **Analyze the code first** — don't guess. Read the relevant controller, queries, and component to understand WHY data appears differently or why the page feels overloaded.
2. **Explain the root cause** — separate the data sources (e.g., "these are notificaciones_enviadas, this is alertas, this is alertas_atendidas — 3 different tables")
3. **Let the user refine** — after they understand the landscape, they'll clarify what they actually want (e.g., "the admin should see everything + the WhatsApp responses")
4. **Propose a concrete redesign** — offer a simplified structure with fewer tabs/sections. Present options to choose from.
5. **Wait for confirmation** before coding

**Pitfall: "The user is confused, let me just explain"** — explaining without offering a fix frustrates them. Always follow diagnosis with a concrete improvement proposal.

**Pitfall: User comes back reporting duplicates after deploy** — When a page uses a JOIN that is 1:N (e.g., `notificaciones_enviadas` has multiple rows per `alertas`), the user will notice duplicates immediately. Always check join cardinality before deploying:
- Is this a 1:N relationship? → Use GROUP BY, DISTINCT, or ROW_NUMBER() to deduplicate
- Will the user notice? Yes — they scan data row by row
- Fix fast: subquery or CTE + ROW_NUMBER() to pick one representative row per parent

### Phase 5: Write the plan

Use the `plan` skill to write a concrete markdown plan with:
- Exact files to modify (and which NOT to modify)
- Business logic steps
- DB migrations if any
- API endpoints
- Frontend components

### Phase 6: Wait for confirmation

Present the plan and wait for explicit confirmation ("go ahead", "yes", "OK", "continue", "do it") before implementing.

If the user says "continue" or "go ahead with all of that plan", proceed.

**Confirm design divergences as questions, not proposals.** Planners and AI
delegates habitually "improve" the source design (swap roles, add manual
triggers, extra endpoints) and Jhonny routinely overrides them with the
the fidelity-to-source answer ("let's make the roles but don't assign any",
"there's no need for a manual OT", then "B" = faithful to Fractal). Present each
divergence as a short A/B question with the evidence (foundation doc/schema),
implement only what he picks. Fidelity to the source doc is the default;
the enum `origen='manual'` and "solicitud normal → OT correctiva" were
already in the reference design — read the source doc before deciding
something is missing.

### Phase 7: Implement with separation

- Keep new features parallel to existing ones — don't refactor or remove old code unless explicitly asked
- Commit frequently after each logical step
- Verify compilation after changes

### Phase 7.5: Ephemeral features (import / temporary overlay)

When building features that import or overlay data from OTHER parts of the system (sensors from other assets, readings from another org, etc.) and the user explicitly says "nothing is saved, it's temporary":

- **State goes in memory only** — `useState`, `useRef`, no `localStorage`/`sessionStorage`. On page refresh or navigate away, the state resets automatically.
- **Clear on asset change** — if the feature depends on a `selectedActivoId` (or similar parent entity), clear the imported state in the same `useEffect` that clears other per-asset state (secondary sensors, etc.)
- **Fetch on import, not on mount** — don't pre-fetch data for all possible targets. Fetch only when the user selects items in the modal and confirms.
- **Modal pattern**: compact modal with search + expandable tree (asset → sensors), multi-select checkboxes, confirm button. Avoid loading ALL data upfront — load on expand.
- **Label format**: when showing items from another context, use `SourceName | ItemName` (pipe-separated) in both pills and chart legends.

### Phase 7.6: UI feedback iteration (post-deploy / post-commit)

After the first working version, the user will test the UI and give visual corrections. Expect 1-3 rounds of refinement. Common corrections:

- **Label format**: user may dislike separator characters (`—`, `-`, `·`) — they prefer `|`.
- **Placement**: user will reject separate UI sections (badge strips, sidebar widgets) in favor of **inline integrated controls** — auxiliary items should be pills/checkboxes inside existing fieldsets, not standalone blocks.
- **Compactness**: user wants the densest possible layout that doesn't lose clarity. Avoid padding-heavy modals or sections with lots of whitespace.
- **Button labels**: user prefers text labels alongside icons (`Import`, `PNG`) over icon-only buttons. Don't guess — if you're unsure, lean toward explicit text + icon, not icon alone.
- **Chart overlay distinction**: when overlaying multiple datasets on the same chart (imported sensors, compared readings), use TWO visual axes for distinction:
  1. **Separate color palettes** — local/primary data keeps the existing palette, overlaid/imported data gets a distinct palette (cool tones = cyan/blue/indigo/teal vs warm/neutral for locals)
  2. **Dash patterns** (`borderDash` in Chart.js) — locals stay solid, overlaid items cycle through distinct dash patterns: `[6,3]` dash, `[3,3]` dot, `[8,3,2,3]` dash-dot, etc.
  This lets the user tell datasets apart without the legend; the pattern-group (solid vs dashed) instantly separates primary from overlaid data. Thread `borderDash` through your type chain: `AdditionalDataset → DashboardChartDataset → Chart.js dataset config`.

- **Color palette design rules (enterprise/IoT dashboards)**:
  - **NO childish/flashy colors**: no pink, no neon, no pastel, no bright purple. User will reject these ("looks like Disney").
  - **Use SAP/enterprise-style colors**: professional blues, teals, greens, muted browns, grays, navy. SAP reference: `#0070F2` blue, `#2B7C6B` teal, `#6BA34A` green, `#1C2D3D` navy, `#6A6D70` gray.
  - **Threshold line colors are FIXED** (critical red `#DC2122`, deficient yellow `#FDB813`). Any sensor/overlay palette MUST have ALL colors with RGB Euclidean distance Δ > 150 from BOTH threshold colors. Check programmatically:
    ```python
    th_r, th_y = (220,33,34), (253,184,19)
    dr = abs(r-th_r[0])+abs(g-th_r[1])+abs(b-th_r[2])
    dy = abs(r-th_y[0])+abs(g-th_y[1])+abs(b-th_y[2])
    assert dr > 150 and dy > 150
    ```
  - **Zero overlap** between local and imported palettes — no shared hex values across palettes.
  - **Alternating hues** between adjacent palette entries for max distinguishability (skip close neighbor hues, vary lightness).
  - **Threshold lines themselves**: use `borderDash: [4, 3]` at `borderWidth: 1.2`. No sensor line uses this pattern — locals are solid thin (~0.95px), imported are dashed at `1.2px` with patterns like `[6,3]`, `[3,3]`, `[8,3,2,3]` (max dash segment 12px), thresholds are uniquely fine-dash at 1.2px.\n  - **Cross-tab sensor DnD**: HTML5 Drag and Drop via `dataTransfer.setData('text/plain', ...)` works across same-origin Chrome windows. Implementation: make sensor pills `<span draggable={true}>` with `onDragStart` setting JSON payload. Drop zone is a `<div>` inside `fieldset.Sensores` with `onDragOver`/`onDrop`. On drop: parse JSON, create `ImportedSensorEntry`, assign color, fetch series data. Visual: `isDragOver` state + `.tt-drop-highlight` CSS class (outline dashed blue). All imported state clears on asset change. Cross-window: Chrome same-origin carries dataTransfer between tabs on different monitors. BroadcastChannel `noustrack-cross-sensor` is fallback.

**Approach**: each round is a fast edit → commit → present. No need to re-plan the full feature. The user already validated the concept; now it's pixel-pushing.

### Phase 8: Deploy (when user says "commit, push, and deploy")

After implementation and verification:

```bash
# Commit and push
git add <files>
git commit -m "feat(x): concise description"
git push origin main

# Deploy to production (SSH)
ssh root@167.172.133.220
cd ~/app && git pull && docker compose -f docker-compose.prod.yml build --no-cache frontend backend && docker compose -f docker-compose.prod.yml up -d frontend backend

# Verificar
docker compose -f docker-compose.prod.yml ps
```

- Check `deploy.md` in the project root for the exact deploy command
- After SSH deploy, verify with `docker compose ps` that all services are "Up"
- If the deploy.md says SSH is available, try it before assuming it's not

### Phase 9: Post-deploy feedback loop

After deploy, the user will test and come back with screenshots or observations. This is NOT a failure — it's part of the flow:

1. **User reports issue** (duplicates, missing data, wrong behavior) → do NOT defend the implementation. Accept the feedback.
2. **Analyze the root cause** — read the actual query/component output. The issue is almost always:
   - JOIN cardinality wrong (1:N producing duplicates)
   - Filter too restrictive (data missing)
   - Filter too permissive (wrong data showing)
3. **Fix, commit, push, deploy** — same cycle, no need to re-explain the full feature. The user already approved the design; now it's iteration on implementation detail.
4. **Label versions clearly** — `v0.4.58` was the redesign, `v0.4.59` was the dupes-and-motivo fix. The user sees the version in the footer.

**Key principle**: A bug found after deploy is not a regression — it's a gap that only becomes visible in production data. Fix fast, don't apologize.

## Pitfalls

### "But I already know what they want"
No, you don't. The user has context you don't. Let them finish.

### "This is a small change, I can just do it"
Small changes in unfamiliar territory cause big reverts. Follow the flow anyway.

### "The existing page already does most of this"
The page might be wrong for the requirement. Don't amend a broken design — confirm the design first.

### "I'll just add this one more thing while I'm here"
Scope creep. If the user didn't ask for it, don't add it. Stick to the confirmed plan.

### Touch nothing unmentioned
If the user talks about "new templates for asset type" and doesn't mention the old "templates for asset" system — leave it alone. Don't touch, refactor, or remove it.

### "Why didn't you delegate this?" — ADD (2026-08-07): IO-heavy frontend that fails repeatedly

The subagent is slower than your direct execution when the bottleneck is IO
(network timeout, large files to re-read). Signs to do it directly (DO NOT delegate):

1. The subagent failed 2-3 times in a row with the SAME pattern (e.g. Sprint 6 frontend:
   3 intents died on connection timeouts without writing code). Don't re-dispatch.
2. The task creates many files (8+ pages) and the context includes files >300 lines that
   the subagent re-reads, blowing its budget. Keep the context narrow:
   exact endpoints + one-page pattern, never the whole backend.

Recovery: direct write_file + temporary ad-hoc script (hermes-verify-* prefix, in the
OS temp dir, deleted after running). Verify with npx tsx script.ts, not with the CLI.

The user may ask why you're working sequentially instead of spawning subagents. Know when NOT to delegate:

- **Single large file**: when changes touch one big file (>500 lines), do NOT delegate. Subagents lack the full file context and will produce conflicting edits, miss state dependencies, or break existing code. Sequential patches are safer.
- **Tightly coupled files**: when a new component and its consumer must match types/props exactly (e.g., a modal component and the 3000+ line page that renders it), delegate only if the subagent receives the full type definition and consumer context. Otherwise sequential is faster than merging — the subagent won't know the full scope of the parent file's state management.
- **Good delegation candidates**: independent tasks on different files that don't share state — parallel API endpoints, separate components with defined interfaces, backend + frontend when the contract is fixed.

## Verification

After implementation:
- Run `npx tsc --noEmit` (backend + frontend) to verify compilation
- Check that only the intended files changed (`git diff --stat`)
- Verify data filtering: does the right user see the right data?
- **Ad-hoc verification script**: for changes across multiple files (new endpoints, new frontend pages), create a focused temporary script that checks:
  - Exports are correct (grep for exported functions)
  - Routes register the new endpoints
  - API types match the backend response shape
  - Component has the expected structure (tabs, sections)
  - Then clean up the temp script
