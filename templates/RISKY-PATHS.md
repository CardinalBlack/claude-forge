# Risky Paths

Files matching these patterns require:
- Read-before-edit (enforced by hook)
- Pre-flight checklist (enforced by skill invocation)
- code-reviewer subagent before claim of done (enforced by Stop hook)
- Definition-of-done filled completely (enforced by Stop hook)

## Default risky-path patterns (every project)

- `**/*auth*/**`
- `**/middleware.{ts,js}`
- `**/migrations/**/*.sql`
- `**/*secret*` (if any escape the hook block)
- `**/api/**` (server-side routes)
- `.github/workflows/**`
- `package.json` (dependency / scripts changes)
- `tsconfig.json`
- `.env.example` (env contract changes)

## Project-specific additions

(populate per project — see project install)
