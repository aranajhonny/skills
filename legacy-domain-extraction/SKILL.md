---
name: legacy-domain-extraction
description: >-
  Extract valuable business logic, domain patterns, schemas, and rules from
  legacy codebases (PHP, any language) into structured reference documentation
  (.md). Focus on what's still relevant today, not the code quality.
trigger: >-
  extraer, legado, legacy, dominio, negocio, lógica, nous, plumrose,
  documentar, referencia, schema, reglas de negocio, reverse engineer,
  ingeniería inversa, knowledge preservation
---

# Legacy Domain Extraction

## Purpose

When analyzing a legacy system, the goal is NOT to critique the code quality (that's a separate activity). The goal is to **extract the durable domain knowledge** — business rules, data models, workflow patterns — that remain valid regardless of the implementation language or framework.

This is particularly valuable when:
- The legacy system is being replaced but the domain knowledge lives in the code
- The original developers are gone and nobody knows why things work a certain way
- You need to understand what a system does before you can design its replacement

## Process

### Phase 1: Explore

1. **Map the directory structure.** List all top-level directories — each one is likely a module/feature.
2. **Identify the module pattern.** Legacy PHP CRUD systems almost always follow `agregar/editar/listado/ver.php` per module. The INSERT queries in `agregar.php` reveal the schema.
3. **Note cross-cutting concerns.** Look for shared includes (`complementos/`, `include/`, `lib/`) — these reveal the infrastructure (auth, DB connection, audit, permissions).

### Phase 2: Extract per module

For each module:

1. **Read the INSERT query** in `agregar.php` — this is the schema. Extract column names, types, and foreign keys.
2. **Read the validation chain** — the `if(empty(X))` blocks reveal required fields and business rules.
3. **Read the SELECT queries** in `listado.php` and `ver.php` — these reveal joins, filters, and how entities relate.
4. **Read the UPDATE logic** in `editar.php` — reveals what can change and what's immutable.
5. **Note any calculated fields** — fields derived from other fields (e.g., estatus calculated from dates).
6. **Extract enums and constants** — hardcoded strings in the code are business vocabulary.

### Phase 3: Document

Each document should contain:

```markdown
# Module Name

## Concept
One paragraph explaining what this module does in business terms.

## Schema
SQL table definition extracted from INSERT queries. Include foreign keys.

## Business Rules
Numbered list of rules as principles, not as code.

## Relevance YYYY (current year)
Why this pattern is still valuable/not valuable today.
```

### Phase 4: Cross-reference

Document the **pipeline** — how modules connect:
- How does an alert in module X trigger an action in module Y?
- What's the lifecycle of a business object across modules?
- Where does data enter the system and where does it exit?

## Output format

Use the `referencia/` directory adjacent to the codebase. Number files as `NN-nombre.md` with a `00-indice.md` as the index.

## Pitfalls

- **Don't get distracted by code quality.** The PHP may be spaghetti, the passwords may be MD5, the HTML may be duplicated 500 times. None of that matters for domain extraction. Note security issues separately but don't let them derail the domain analysis.
- **Don't assume you know the schema.** Always verify against actual INSERT queries, not comments or out-of-date documentation.
- **Don't fabricate.** If you can't determine a relationship or rule from the code, say "unknown" or "probable" — don't invent.
- **Don't over-abstract.** Legacy systems often have hardcoded values that look like bugs but are actually business rules. A hardcoded `id_estatus = 31` is a business rule, not a magic number.
- **Save the output as reference docs, not as session memory.** The value is in the durable .md files, not in conversation history.
