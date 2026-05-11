---
name: pre-flight-checklist
description: Use BEFORE any non-trivial code change (any task with >2 file edits, or any change to files in RISKY-PATHS.md). Forces an explicit pre-flight pass so Claude doesn't dive into tool calls without orienting.
---

# Pre-Flight Checklist

Before the first Edit / Write of a non-trivial task, output the following block in chat (verbatim format), filling each section. Do NOT call tools until this is complete and the user has had the chance to redirect.

## Files I'm about to touch

- (list every path you will Edit / Write / Read deeply)

## Files I will Read first to orient

- (list paths you will Read BEFORE editing — schemas, related modules, tests)

## Tests that will prove this works

- (list test files you will create or extend; describe what they assert)

## What I'm assuming that I haven't yet verified

- (list assumptions: schema shapes, library behavior, env vars present, etc.)

## What could go wrong (3 failure modes)

- (list 3 specific failure modes — not generic; specific to this change)

## Definition of done

- (an observable criterion the user could verify themselves)

---

After outputting the block, wait one short message exchange. If the user does not redirect, proceed with the Reads listed under "Files I will Read first to orient" before any Edit.
