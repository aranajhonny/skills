#!/bin/bash
set -e
cd ~/.hermes/skills

# exact filenames in code-quality-review (curiosity + verification)
echo "=== code-quality-review actual files ==="
ls -b software-development/code-quality-review/

SKILLS="software-development/ai-generated-code-review
software-development/systematic-debugging
software-development/test-driven-development
software-development/feature-workflow
software-development/legacy-domain-extraction
software-development/spike
software-development/simplify-code
software-development/requesting-code-review
software-development/code-quality-review
software-development/delegation-patterns
software-development/infrastructure-build-analysis
devops/database-schema-review"

for s in $SKILLS; do
  name=$(basename "$s")
  for dest in ~/lab/skills ~/.agents/skills; do
    rm -rf "$dest/$name"
    cp -R "$s" "$dest/$name"
  done
done

EXCLUDES="ai-generated-code-review/worker-entry-points-manual-trigger.md
ai-generated-code-review/worker-mantenimiento-review.md
code-quality-review/noustrack-plumrose-session.md
code-quality-review/external-audit-review-and-sql-migrations.md
delegation-patterns/sprint-coder-context.md
delegation-patterns/hermes-root-agent-no-autonomous-delegation.md
delegation-patterns/hero-to-navbar-refactor.md
delegation-patterns/missions-plugin-python-invocation.md
database-schema-review/iot-sensor-order-audit.md
infrastructure-build-analysis/lumen-case-study.md"

for dest in ~/lab/skills ~/.agents/skills; do
  for f in $EXCLUDES; do
    rm -f "$dest/$f"
  done
done

find ~/lab/skills ~/.agents/skills -name '.DS_Store' -delete 2>/dev/null || true

echo "=== new tree in lab/skills ==="
for n in ai-generated-code-review systematic-debugging test-driven-development feature-workflow legacy-domain-extraction spike simplify-code requesting-code-review code-quality-review delegation-patterns infrastructure-build-analysis database-schema-review; do
  echo "-- $n"; find ~/lab/skills/$n -type f | sed 's|.*/skills/||'
done

cd ~/lab/skills
git add -A
git status --short
git commit -q -m "Add 12 top-tier agnostic engineering skills from Hermes (stripped of project/session files)" || echo "nothing to commit"
git push -q origin main && echo "=== PUSHED ==="