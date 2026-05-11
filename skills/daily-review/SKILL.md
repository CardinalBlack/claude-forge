---
name: daily-review
description: Cron-invoked. Audits the last 24h of activity in this repo and outputs a digest covering commits, MISTAKES.md additions, SESSION-STATE drift, unmet commitments, and any concerning patterns.
---

# Daily Review

Output a markdown digest with these sections:

## Activity (last 24h)
- Commits: list with SHA + subject + author
- Files most-touched: top 5
- Branches active: list

## MISTAKES.md additions (last 24h)
- New entries with one-line summaries
- Pattern flags: are recent mistakes clustered in one file or one type?

## SESSION-STATE.md drift
- "Last Updated" timestamp vs latest commit timestamp
- Sections that haven't moved in >7 days
- Items in "In Progress" longer than 3 days

## Unverified claims
- Search the last 24h of session logs for "done", "passes", "verified", "fixed"; cross-reference with test runs in the same window. Flag any unbacked claims.

## Concerning patterns
- Repeated edits to the same file (>3 in 24h) — possible architecture issue
- Test suite size shrunk vs. yesterday — coverage regression?
- New TODO / FIXME / HACK comments — list them with file paths

Save the digest as `reports/daily/YYYY-MM-DD.md`. If anything looks alarming, also output a Slack-ready summary the user can act on.
