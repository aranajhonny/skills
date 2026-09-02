---
name: code-quality-review
description: >
  Evaluate codebases qualitatively — architecture, security, domain value,
  maintainability, and team context. Complements quantitative codebase-inspection.
  Extracts valuable domain concepts from legacy/messy code instead of just trashing it.
version: 1.0.0
author: Hermes Agent
tags:
  - code-quality
  - legacy-code
  - code-review
  - architecture
  - domain-value
  - php
  - postgresql
related_skills:
  - codebase-inspection
  - requesting-code-review
---

# Code Quality Review (Qualitative)

Analyze a codebase's quality beyond LOC metrics. Read representative files, assess architecture, security, and extract what's actually valuable.

## When to Use

- User asks "analyze this project", "how's the code", "code quality review"
- User wants an honest assessment of a legacy system
- User wants to know what's worth keeping vs rewriting
- User wants domain concepts extracted from messy implementations
- Any evaluation where the real question is "is this codebase any good?"

## Methodology (6 phases)

### Phase 1: Quick Scan

Get the lay of the land before reading a single line of code:

```bash
# Count files by type
find /path -type f -name "*.php" | wc -l
find /path -type f -name "*.js" -o -name "*.ts" | wc -l
find /path -type f -name "*.py" | wc -l

# Check for framework indicators
ls -la composer.json package.json Makefile Dockerfile docker-compose.yml Cargo.toml

# Check for router/entry point
cat index.php server.js main.py app.py 2>/dev/null | head -20

# Check dependency manifest
cat composer.json package.json requirements.txt Cargo.toml 2>/dev/null
```

**Key signals**:
- One file at root vs directory structure → flat vs organized
- Composer/package.json present → has dependency management
- Dockerfile present → containerized
- config/ directory present → separation of concerns

### Phase 2: Read the Core Infrastructure

Identify and read the foundation files that tell you how the system works:

```
Always read first:
  ├── index.php / server.js / main.py → entry point, architecture style
  ├── config / .env / settings → how secrets are managed
  ├── DB connection file → connection strategy (hardcoded? pooled? ORM?)
  ├── Auth / session / login → security baseline
  └── Router / middleware → framework or custom?
```

**What to look for**:
- **Hardcoded credentials** → "host=localhost user=postgres password=xxx" in 100 files = critical
- **Password hashing** → md5() vs bcrypt/argon2 = security era
- **SQL construction** → prepared statements vs concatenation = injection risk surface
- **Session management** → custom vs framework = fragility indicator

### Phase 3: Read Representative Feature Files

Pick 2-3 feature modules and read one CRUD cycle (add/create, list, view):

```php
// Pattern to recognize: flat script vs layered
// Bad: One file does HTML + SQL + validation + session state
// Good: Controller calls Service calls Repository renders View
```

**The multi-layer check** — in legacy PHP+PostgreSQL systems, the REAL logic is often in the database:

```
ALWAYS ASK: Is the PHP thin and the DB fat?
  ├── PHP does simple INSERTs, complex behavior comes from triggers?
  ├── PHP does SELECT * but joins/aggregations are in materialized views?
  ├── Business rules (status calculation, cascades, validations) in PL/pgSQL?
  
  Signals:
  - INSERT without business validation → trigger in DB does it
  - No complex JOINs in PHP → a materialized view handles it
  - Magic numbers mapping to nothing visible → they're in DB functions
```

**Context matters**: If the system is from ~2012-2014 and built by students or DBAs-turned-devs, the split between PHP and DB logic reflects their background. Don't judge by modern standards alone.

### Phase 4: Security Assessment (Legacy)

For legacy PHP systems specifically:

| Check | What to Look For | Severity |
|---|---|---|
| SQL injection | Variables interpolated without escaping in pg_query/mysqli_query | 🔴 Critical if found |
| Password storage | md5(), sha1(), or plaintext | 🔴 Critical |
| Hardcoded creds | DB password repeated across files | 🔴 Critical |
| XSS | $_SESSION messages echoed into <script> without escaping | 🟡 High |
| CSRF | Forms without tokens | 🟡 High |
| Session | Cookie flags (Secure, HttpOnly, SameSite) | 🟡 Medium |
| File upload | Unvalidated file types, direct path storage | 🟡 High |

**Important**: Some "insecure" patterns from 2012 (like whitelist character filtering via `filtrar_campo()`) were actually decent for their era and more effective than modern prepared statements alone. Acknowledge context before condemning.

### Phase 5: Extract Domain Value

**This is the most important phase.** Bad code can hide great domain models. Extract what's valuable before dismissing the system:

```
Look for:
  ├── Entity hierarchies that reflect real business structure
  ├── Status/workflow state machines (e.g., permission statuses, maintenance cycles)
  ├── Scheduling/dispatch patterns (incremental vs cyclical, tolerance bands)
  ├── Composition/decomposition of assets (equipment → parts → components)
  ├── Access control structures (ACL by module/form/action)
  ├── Audit trails (who did what, when, from where)
```

**The legacy paradox**: a 2014 PostgreSQL schema designed by domain experts (even if they were students) often has better entity modeling than a 2024 microservices API. The schema is knowledge distillation, the PHP is just the paint job.

### Phase 6: Deliver the Assessment

Structure the output so the user gets maximum signal:

```markdown
## Summary
One-liner: era, language, framework (or lack thereof), production status.

## Architecture
Score /10 with specific reasons. Pattern identified (MVC? Spaghetti? Thin-over-DB?).

## Security
Score /10. Critical issues first, then context-era defenses that still work.

## Maintainability
Score /10. Code organization, duplication, naming, error handling.

## What's Valuable
The domain concepts, schema patterns, or workflows worth keeping/rebuilding.

## Overall
Score /10 with honest commentary. "Runs in production but hurts to maintain" > "It's garbage".
```

## Pitfalls

1. **DO NOT ignore the DB layer** — in legacy PHP+PostgreSQL systems, the real logic is often in triggers, functions, and materialized views. The PHP may be just a thin presentation layer.
2. **DO NOT judge 2012 code by 2024 standards** — evaluate within its era. Whitelist filtering was a legit defense before prepared statements were universal.
3. **DO NOT say "just rewrite it"** without extracting what's valuable from the existing implementation. The domain model took years to evolve.
4. **DO NOT read all 500 files** — read 5-10 representative ones. The patterns repeat.
5. **DO NOT ignore team context** — "students in Venezuela" explains a LOT about code quality. Acknowledge it.
6. **DO NOT mock what worked in production** — a system that ran Plumrose's operations for years deserves respect even if the code is ugly.
7. **Contextualize the security review** — hardcoded credentials are bad, but in an era before CI/CD, before containers, on an internal network, they were the norm. Be honest but not theatrical.

## Techniques for Legacy PHP Analysis

### Detecting thin-client-over-DB pattern

Signs that the real logic is in PostgreSQL:
- PHP files are short (200-400 lines) and do simple INSERT/SELECT
- No business rule validation in PHP before INSERT
- Complex SELECTs reference `vista_*` (materialized views)
- `pg_query()` calls use raw concatenation but pass through `filtrar_sql()` wrapper
- No ORM, no query builder — just raw SQL in strings
- Triggers are detected by: INSERTs that have no status/state updates in PHP but data has computed columns

### Combo/dependency pattern

Legacy systems use AJAX-driven dependent selects (select → onchange → fetch child options):
- Each dependency has its own PHP file: `dependencia_unidades.php`, `dependencia_areas.php`, etc.
- Files return HTML `<option>` strings, not JSON
- Pattern is brute-force but effective for deeply nested catalogs

### Session-as-state-machine

Legacy PHP systems use `$_SESSION` to pass state between multi-step forms:
- `$_SESSION['master']` holds the current object being created
- `$_SESSION['tmp_req']` holds temporary data before commit
- Fragile but functional — the session IS the transaction buffer
