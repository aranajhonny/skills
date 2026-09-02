# Root Agent Autonomous Delegation Gap

Date discovered: 2026-07-20
Source: Session con Jhonny — "llevo 1 mes usando hermes nunca hace delegate_task"

## The Problem

Hermes root (primary conversation) agent has `delegate_task` available as a
tool but never autonomously decides to use it for task decomposition.

## Root Cause

The system prompt block that tells the agent *when* to delegate is only
injected into subagents created with `role='orchestrator'`. The root agent
never gets this instruction.

### Code Location

**Orchestrator guidance injected here (subagents only):**
`tools/delegate_tool.py:717-736`

The function `_build_child_prompt()` builds the system prompt for
subagents. At line 706 it checks `if role == "orchestrator"` and only then
appends the "Subagent Spawning (Orchestrator Role)" section:

```python
if role == "orchestrator":
    parts.append(
        "\\n## Subagent Spawning (Orchestrator Role)\\n"
        "You have access to the `delegate_task` tool and CAN spawn "
        "your own subagents to parallelize independent work.\\n\\n"
        "WHEN to delegate:\\n"
        "- The goal decomposes into 2+ independent subtasks that can "
        "run in parallel (e.g. research A and B simultaneously).\\n"
        "- A subtask is reasoning-heavy and would flood your context "
        "with intermediate data.\\n\\n"
        ...
    )
```

**Root agent system prompt built here:**
`agent/prompt_builder.py:139-147`

```python
DEFAULT_AGENT_IDENTITY = (
    "You are Hermes Agent, an intelligent AI assistant created by Nous Research. "
    ...
)
```

No mention of delegation, decomposition, or subagent spawning. The root
agent identity is that of a "helpful assistant," not a "planner that
decomposes and delegates."

## How to Fix

Two approaches, both involve injecting an explicit instruction into the
system prompt:

### 1. Project Context File (`.hermes.md` or `AGENTS.md`)

```markdown
For complex multi-file tasks (refactors, features, batch edits), you
MUST decompose the work into independent subtasks and use
`delegate_task` to parallelize them. Do not edit files one by one
sequentially when subtasks are independent.
```

### 2. Skill Loaded at Session Start

Create a skill that says the same thing and load with `/skill name` or
`hermes -s name`.

## Architectural Note

Cursor's enjambre is built FROM the ground up as a planner→worker
architecture. Hermes is single-agent with an optional delegation tool.
These are fundamentally different paradigms — Hermes needs explicit
prompt-level steering to behave like a swarm.
