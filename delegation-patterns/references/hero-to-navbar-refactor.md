# Concrete Example: Removing tt-home-hero Across 21 Pages

This was a real session where delegation-patterns was applied. 21 React
pages (table views + form/assignment/dashboard pages) had a
`<div className="tt-home-hero flex-shrink-0">` block (eyebrow + h1 +
subtitle + action buttons) that wasted vertical space.

The goal: remove the hero block, push title/subtitle into the Navbar
via PageHeaderContext, and move action buttons into the existing
toolbar (or create a mini toolbar).

## Pattern Applied to Each File

1. **Add import**: `import { usePageHeader } from "../contexts/PageHeaderContext";`
2. **Add hook**: `const pageHeader = usePageHeader();` after function declaration
3. **Add useEffect**:
   ```tsx
   useEffect(() => {
     pageHeader?.setHeader?.({ title: "...", subtitle: "..." });
     return () => { pageHeader?.setHeader?.({}); };
   }, []);
   ```
4. **Remove** the entire `<div className="tt-home-hero flex-shrink-0">` block
5. **Move** action buttons into the toolbar (the `bg-white border border-gray-300 p-3 sm:p-4` div)

## Navbar Enhancement

The Navbar component was updated to show title + subtitle in a single inline line:
- Title: `text-base xl:text-lg font-extrabold` (big and bold)
- Subtitle: `text-xs xl:text-sm text-gray-500 hidden xl:inline` (smaller, beside title)
- Layout: `flex items-baseline gap-2` instead of stacked divs

Previously the title was `text-xs xl:text-sm` and the subtitle was
stacked below in `text-[10px] xl:text-[11px]`.

## Full 21-Page File List

### Table-list views (batch-delegated)
- ActivosList, OrganizacionesList, DepartamentosList, UbicacionesList
- CategoriasActivoList, DispositivosList, UsuariosList, ListasCorreos
- EscalamientoList, PlantillasMensajeActivo, PlanosList
- EstadoDispositivos, PermisosAdmin

### Form/assignment pages (handled manually)
- DispositivoRegistro, DispositivoAsignarOrganizacion
- DispositivoAsignarActivo, ActivoAsignarSensores

### Dashboard/visual pages
- DashboardPlano (dynamic title from `plano.nombre`)
- XRay (debug telemetry page)
- Dashboard (selection view with area selector + pills)

## Delegation Experience

**3 batches of 3 delegates** (limited by `max_concurrent_children=3`).
Results:
- Batch 1 (Departamentos, Ubicaciones, CategoriasActivo) → 3/3 OK
- Batch 2 (Dispositivos, Usuarios, ListasCorreos) → 0/3 applied
  (delegates self-reported success but files unchanged)
- Batch 3 (Escalamiento, PlantillasMensaje, Planos) → partial

**Lesson**: At max parallelism, contention causes silent failures.
Always `search_files` after delegation to verify. Fix stragglers
manually with single `patch` calls.

**Recovery pattern**: `git checkout -- <file>` then redo manually.
Do NOT try complex inline patches on broken state.

## Verification

After all changes:
- `search_files` for `tt-home-hero` → 0 matches in all 21 page files
- `search_files` for `usePageHeader` → 1+ matches in all 21 files
- Build: `vite build` → exit 0 (7.5s, 1472 modules)

## Files Modified Outside Pages

- `frontend/src/components/layout/Navbar.tsx` — title/subtitle layout & sizing
