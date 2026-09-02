# Reviewing External Audit Reports & mysqli Dead-Error Patterns

When the user brings a third-party audit/report for opinion (not asking you to audit from scratch), verify before opining:

1. **Verify each finding against the repo FIRST** — read/grep the exact artifacts cited (dump headers, compose files, migration dirs). An audit is worth exactly its facts; agreement without verification is worthless.
2. **Scope-vs-reality check**: reports routinely claim to audit things absent from the checkout (report discussed docker-compose/init.sql; `find -iname "*docker*"` returned nothing). Ask which tree/commit was reviewed and say so explicitly in the verdict.
3. **Flag what the audit MISSES**, especially app-layer security when the audit stays at config/deploy level: unauthenticated destructive endpoints, interpolated SQL, dead error handling, races. Compare its stated max severity against what the hot paths actually contain — a report whose ceiling is "default credentials" while a public DELETE exists did not read the flows.
4. **Correct backward-looking recommendations** ("validate MariaDB because the dump came from there") into forward-looking ones ("pick the target engine going forward, test the import once").
5. Deliver as: verified-correct findings → missed findings with `file:line` evidence → criterion corrections → scope warning.

## mysqli error-handling dead code

- `try/catch` around `mysqli_query()` does NOTHING unless `mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT)` was set — mysqli returns `false` and emits warnings instead of throwing. Catch blocks around mysqli calls mean write failures are silently unhandled.
- Related same-era flaw: SELECT-then-UPDATE decision flows without transactions (race between concurrent clients duplicates state).
- Recognize legitimate-looking destructive ops before condemning them: e.g. a DELETE endpoint may be a compensating transaction (delete record when ticket printing failed — see `interfaz_grafica.py` ELIMINAR callers). Still needs auth, but the design intent matters for the review's credibility.

## Framework-less SQL migrations (user's chosen pattern)

When a Laravel (or any ORM-framework) codebase is slated for rewrite, framework-coupled migrations are wasted work. User-approved pattern:

- Baseline: generate `init.sql` ONCE from the live schema, validate against the target engine (e.g. MySQL 8.0 import test), then NEVER edit it again — all evolution goes through new migration files.
- Migrations: plain `.sql` files, zero-padded sequence prefix + description (`0001_add_user_name.sql`). Date-based names (`add_x_21_08_2026.sql`) sort alphabetically wrong across months and are ambiguous same-day — reject them.
- Ledger: dumb table `schema_migrations(name, applied_at)` + ~20-line bash runner applying pending files in order. Framework-agnostic, survives the rewrite.
- Keep migrations in a versioned dir (`db/migrations/`) — if `/database` is gitignored (common in these repos), reusing it silently excludes migrations from version control.

## API contract extraction from legacy clients

Before documenting an undocumented internal API, mine the actual callers rather than only the server:
- Client-side request builders show every action/payload variant actually used (grep `"accion"` / action field in .py clients).
- Existing `.http` files (VS Code REST Client format) often already enumerate the actions — expand from there.
- Document response fields per action and timezone quirks: e.g. client sends `int(time.time()) - 14400` (UTC-4 offset baked into the client) while server uses raw `time()` — this coupling breaks rewrites silently if undocumented.
- Decorative protocol fields (request `ok: true` never read by server) belong in the doc so the rewrite doesn't cargo-cult them.
