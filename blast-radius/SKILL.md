---
name: blast-radius
description: "Use for 'what could this change break', 'blast radius of X', or reviewing a small diff you don't trust. Find the one fact the change is safe because of and prove it by running real code, instead of writing up a convincing-sounding analysis."
---

# Blast radius

Find what a change breaks somewhere else, before it ships.

Listing the callers is not the job. The agent can grep those in a second. The job is the breakage grep won't show you: when things run, what a symbol search misses, another language reading the same bytes, a feature flag, code three hops downstream.

## Don't trust your own writeup

A blast-radius writeup that sounds right is worthless. It reads as convincing whether or not it's true. So don't hand back the writeup. Find the one or two facts the whole thing depends on and prove them by running code.

### How sure are you

For each fact the change's safety depends on, get it as far down this list as is cheap, and say where it stopped.

1. You said so. Worthless on its own.
2. You pointed at the line. A real `file:line`, or the library's own source.
3. You showed the bad case can't happen. You walked the failure step by step and it doesn't reach.
4. You ran it. A script or test that calls the real code and fails loud if you're wrong.
5. You reproduced it in the running app.

Any safety fact you can't get to step 4, say so out loud. Step 4 is usually one small script that imports the same library the app ships and calls the exact function you're worried about.

## Steps

1. Read the change — the diff, the symbols it adds, changes, and deletes, and what it now does differently, including the part the diff doesn't spell out. Pull the PR and commits with `gh`.
2. Find the one fact it's safe because of. Most scary-looking changes are safe because of a single fact ("this call only drops already-dead cache entries and does nothing else"). Find it. If it holds, most of the scary cases die at once.
3. Look where grep stops. Read the source of the library you call and check its pinned version and any local patch. Work out when things run: microtasks, unmount and teardown, Solid versus React. Follow what a symbol search misses: the JSON an API returns, a DB column, a wire format, another language reading the same bytes.
4. Be honest about each risk. Give it a real chance of happening and a real cost if it does. Keep the confirmed risks; list the checked-and-cleared separately. Never make up a caller or an API.
5. Prove the one fact. Write a script or test that runs the real code, run it, and paste what happened. If you can't prove it cheaply, mark it unproven.
6. For a big or wide change, fan out to several subagents with the same question and merge the answers. Different models catch different real bugs.

## What to hand back

- **What it does.** What changed, including the part that isn't obvious.
- **The one fact it's safe because of.** State it, say which step you got it to, and show the proof. If you couldn't prove it, write unproven.
- **Risks.** Only the real ones. Each names how it breaks, the `file:line`, how likely and how bad, and how to check.
- **Cleared.** What you checked and why it's fine.
- **Before you merge.** The cheapest test or repro that catches the real bug, including the script you wrote.

Strip anything private before it goes anywhere public.
