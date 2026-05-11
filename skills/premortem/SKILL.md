---
name: premortem
description: Invoke at the START of any phase or any task estimated > 4 hours. Forces explicit thinking about what could go wrong before code is written, not after a bug ships.
---

# Premortem

Before tool calls, output:

## "Imagine this phase shipped and broke. What were the 3 most likely failure modes?"

For each failure mode:
1. **Description** — what specifically went wrong
2. **Symptom the user would see** — concrete observable
3. **Root cause hypothesis** — what assumption / oversight / drift caused it
4. **Pre-flight defense** — what test / review / observation would surface it before shipping

## "What would the user catch first?"

Imagine the user pulls this branch and uses it. What's the first thing they'd notice that's wrong?

## "What's the cheapest reversible thing I'd do first to de-risk?"

(e.g., write a smoke test before the feature; mock the integration before wiring; ask a clarifying question)

After outputting these, wait for user redirection if any. Then proceed.
