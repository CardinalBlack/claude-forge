---
name: weekly-audit
description: Cron-invoked weekly. Deeper-cadence audit: ADR drift, mistakes-as-tests reconciliation, dependency staleness, BAA/contract expiry, model deprecations, corpus freshness.
---

# Weekly Audit

Output `reports/weekly/YYYY-Www.md` with these sections:

## ADR drift
- For each ADR in `docs/adr/`, has the actual code drifted from the recorded decision? Sample by spot-checking files referenced in each ADR.

## Mistakes-as-tests reconciliation
- For each MISTAKES.md entry from the past month: does a test, lint, or hook exist that would catch it? List entries WITHOUT corresponding guards. Draft the missing guards.

## Dependency staleness
- Run `pnpm outdated` (or equivalent). Flag any major-version-behind dependency.
- Run `pnpm audit --prod`. Flag any high/critical CVE.

## Model + API deprecations
- For each Anthropic model ID hardcoded or referenced (`claude-opus-4-7`, `claude-sonnet-4-6`, etc.), check Anthropic's current model list. Flag deprecations.

## Corpus freshness (virtual-rep specific)
- For each PM document in `corpus_documents`, compare ingestion date to today. Flag anything > 6 months old.

## BAA / vendor contract expiry
- Read `vendor-compliance.md`. Flag any vendor contract or BAA expiring within 30 days.

## CI green-bar history
- Pass rate over the last 7 days. Trend: improving / stable / degrading?

Save report. Surface alarming items.
