---
name: why
description: "Use for 'why does this code work this way', design rationale, regressions, or 'where did this threshold come from'. Pull git history and PRs, then return a confidence-weighted, cited read on intent — never citing the code as evidence of its own motivation."
---

# Why

Investigate the motivation and intent behind code. Why was it built this way? What edge cases were considered? What constraints shaped the design? What was rejected, and why?

Code tells you what it does, rarely why it exists. The "why" lives in commits, PRs, tickets, docs, and comments — all incomplete, biased, and sometimes missing. The job is to surface evidence, calibrate confidence, and let the user decide, not to tell a satisfying story.

## Operating posture

- **Evidence before narrative.** Collect the pieces first, then see what story they support. Never pick a story and recruit the evidence that fits it.
- **Cite everything.** A claim about intent needs a commit hash, PR number, ticket ID, doc URL, or code comment. No citation means inference, and it must be labeled as inference.
- **Code is not evidence of intent.** "It checks for null because it handles the null case" is mechanics, not motivation. Motivation comes from an external source, or it's labeled inference.
- **Name the gaps.** An honest "we couldn't find out why" beats a confident guess the user will act on.
- **Hedge on purpose.** Use "appears to", "likely", "suggests" when evidence is indirect.

Read `references/epistemics.md` for the full confidence framework and phrasing guide. Follow it exactly.

## Workflow

1. **Anchor in code.** Identify the target files, line ranges, and key symbols. Pull the last commits touching them and extract PR numbers.

   ```bash
   git blame -L <start>,<end> <file>
   git log --follow --oneline -- <file>
   git log -S '<exact_string>' -- <file>
   gh pr view <number> --json title,body,author,mergedAt,comments,reviews
   ```

2. **Mine the in-repo sources.** See `references/sources/code-archaeology.md` for the full git/gh playbook: commit messages, PR bodies and review threads, code comments, test names, ADRs, changelogs. Start here; it's the most trustworthy source, tied directly to the diff that shipped.

3. **Extend to whatever else you can reach.** If a ticket tracker, doc store, or observability tool is available in this environment, search it for the same symbols and dates. A null result is evidence too: "no ticket discusses this" says the decision wasn't ticketed. Record what you searched and what came back empty.

4. **Synthesize with the epistemics.** For a broad investigation, fan out with parallel subagents — one per source you actually have — using `references/investigator-prompt.md`, then combine with `references/synthesizer-prompt.md`. For a small target, do it inline.

## Output format

Keep the confidence separation intact:

- **The question.** Restate it.
- **The code in question.** Paths, line ranges, key symbols.
- **What we found.** Direct evidence, each with a citation (PR #, commit hash, comment `file:line`).
- **What we can reasonably infer.** Indirect evidence, hedged, with the inference chain shown ("Given A and B, it's likely that C").
- **Competing hypotheses.** If the record fits more than one story, show them all.
- **What we don't know.** Specific gaps and searches that came up empty.
- **Sources consulted.** One line per source, including the empty ones.

If the "why" is a precursor to changing the code, close with a Preserve / Change / Avoid / Risk constraint set for the change.
