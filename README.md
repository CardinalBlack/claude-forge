# claude-bootstrap

Behavior-hardening for [Claude Code](https://claude.com/claude-code) that installs once and runs everywhere: refusal-blocking hooks, a constellation of process skills, independent-verification subagents, per-project templates, and review crons.

The premise is mechanical, not aspirational: rules in your `CLAUDE.md` are easy to drift away from. Tool calls that *can't happen* (because a `PreToolUse` hook refuses them) and context that *is always injected* (because a `UserPromptSubmit` hook always fires) are not. This repo is the second category, dressed up as a reusable bootstrap.

```
~/.claude-bootstrap/             ← this repo, the source of truth
   bootstrap.sh                  ← installs the global layer
   install-project.sh            ← installs the per-project layer
   hooks/                        ← shell scripts wired into settings.json
   skills/, agents/              ← symlinked into ~/.claude/ on install
   templates/                    ← copied into project repos on install
   crons/, scripts/              ← daily + weekly review wiring
```

After `./bootstrap.sh` runs once, every Claude Code session on the machine inherits the global layer — skills, agents, and refusal hooks are available in any CWD. After `./install-project.sh <project>` runs against a project, that specific repo gains MISTAKES.md / DEFINITION-OF-DONE.md / SESSION-STATE.md auto-injection and a project-specific risky-path policy.

## Status

Phases 0 through 6 are shipped. 135 bats tests, CI on every push. Phase 9 polish (this README, operator runbooks, final integration test, v1.0 tag) is in progress. The remaining hardening phases are downstream-project-specific and live outside this repo.

## Quick start

```bash
git clone --recurse-submodules https://github.com/<you>/claude-bootstrap.git ~/.claude-bootstrap
cd ~/.claude-bootstrap
make test          # 135/135 green before you trust it
./bootstrap.sh     # symlink skills + agents into ~/.claude, merge hooks
```

Then, for each project you want to onboard:

```bash
~/.claude-bootstrap/install-project.sh /path/to/your/project
```

Restart Claude Code. The next session sees the new skills, agents, hook output, and per-project context.

## What you get

### Seven refusal / context-injection hooks

Hooks live in `hooks/` and are merged into `~/.claude/settings.json` by `scripts/install-hooks.sh`. The merge is idempotent and preserves any user-managed hooks already present.

| Hook | Event | Behavior |
|---|---|---|
| `must-read-before-edit.sh` | PreToolUse on `Edit\|Write` | Refuses to edit a file that hasn't been Read in this session (60s mtime escape; `CLAUDE_BYPASS_READ_CHECK=1` override). |
| `block-direct-main-commit.sh` | PreToolUse on `Bash` | Refuses `git commit` on `main` / `master` without an `ALLOW-MAIN-COMMIT:` tag in the message or `CLAUDE_ALLOW_MAIN=1` in env. |
| `kill-switch.sh` | PreToolUse on all tools | Refuses every tool call while `~/.claude/PAUSE_AND_REVIEW` exists; emits the file's content as the reason. Delete the file to resume. |
| `inject-mistakes-and-dod.sh` | UserPromptSubmit | Injects the last 10 entries of CWD `MISTAKES.md` plus the full CWD `DEFINITION-OF-DONE.md` into Claude's context every turn. No-op if the files are absent. |
| `inject-session-state.sh` | UserPromptSubmit | Injects the **In Progress**, **Next Up**, and **Active Plan** sections of CWD `SESSION-STATE.md`. Warns when the file's mtime is more than 24 hours old. |
| `require-verification-before-done.sh` | Stop | Scans the recent transcript for "done" claims without a corresponding test / typecheck run, and injects a reminder. Never blocks (Stop hooks can only inject context). |
| `log-read-paths.sh` | PostToolUse on `Read` | Appends every Read path to `~/.claude/state/reads.log`. Powers the `must-read-before-edit` enforcement and gives a forensic trail. |

### Seven process skills

Skills live in `skills/<name>/SKILL.md` and are symlinked into `~/.claude/skills/` by `bootstrap.sh`. Each one is a markdown procedure Claude follows when invoked.

| Skill | When |
|---|---|
| `pre-flight-checklist` | Before any non-trivial code change. Forces an explicit pre-flight: files touched, files to read first, tests, unverified assumptions, three failure modes, definition of done. |
| `definition-of-done` | At the end of any non-trivial task. An 11-row evidence table — any row at NO means the task is not done. |
| `bug-postmortem` | Whenever the user catches a bug. Produces a `MISTAKES.md` entry **and** drafts the test / lint / hook that would have caught it. Both are committed together. |
| `premortem` | At the start of any phase or any task estimated > 4 hours. Three sections: top-3 failure modes, what the user would catch first, the cheapest reversible de-risk step. |
| `session-debrief` | At session end. Updates `SESSION-STATE.md`, drains new `MISTAKES.md` entries, surfaces unmet commitments, verifies typecheck clean, commits. |
| `daily-review` | Cron-invoked. 24-hour digest covering commits, MISTAKES drift, SESSION-STATE staleness, unverified done-claims, concerning patterns. |
| `weekly-audit` | Cron-invoked. Deeper-cadence audit: ADR drift, mistakes-as-tests reconciliation, dependency staleness, model deprecations, BAA expiry, CI green-bar trend. |

### Four independent-verification subagents

Subagents live in `agents/<name>.md` and are symlinked into `~/.claude/agents/`. All four use a read-only tool allowlist (`Read, Grep, Glob, Bash`) — reviewers inspect, they don't edit.

| Agent | Use |
|---|---|
| `code-reviewer` | Independent reviewer for non-trivial changes, especially on `RISKY-PATHS.md` files. Sees the diff and the task description, not the author's reasoning. Returns APPROVE / REQUEST_CHANGES / NEEDS_CONTEXT. |
| `devils-advocate` | Adversarial counterpart to `code-reviewer`. Assumes the change is broken; the task is to find HOW. Concession is not an allowed exit. |
| `task-debriefer` | End-of-task auditor. Verifies the task as actually completed against the original request, demands evidence for claimed verifications, flags quiet deferrals. |
| `daily-auditor` | Cron-invoked. Walks every project in `~/.claude/state/audited-projects.json` and runs `daily-review` / `weekly-audit` against each, aggregating cross-project red flags. |

### Eight per-project templates

Templates live in `templates/` and are copied into a project repo by `install-project.sh`. Existing files are never clobbered.

| Template | Lands at | Purpose |
|---|---|---|
| `MISTAKES.md` | `<project>/MISTAKES.md` | Living institutional memory; injected into every turn by `inject-mistakes-and-dod.sh`. |
| `DEFINITION-OF-DONE.md` | `<project>/DEFINITION-OF-DONE.md` | Project-specific completion bar; injected into every turn. |
| `RISKY-PATHS.md` | `<project>/RISKY-PATHS.md` | Globs/regexes for files that require extra ceremony. Customize per project. |
| `BORING.md` | `<project>/BORING.md` | Inverse of `RISKY-PATHS`: problem domains where novelty is the failure mode (auth, HMAC, migrations, dates, JSON parsing). |
| `SESSION-STATE.md` | `<project>/SESSION-STATE.md` | Recently Completed / In Progress / Next Up / Active Plan / Key Context. Injected (sliced) every turn by `inject-session-state.sh`. |
| `CLAUDE-ADDENDUM.md` | Appended to `<project>/CLAUDE.md` | Marker-based idempotent block wiring the project into bootstrap conventions. |
| `.github/pull_request_template.md` | `<project>/.github/pull_request_template.md` | PR scaffold with inline DoD table + risk + followups. |
| `adr/0000-template.md` | `<project>/docs/adr/0000-template.md` | Architecture Decision Record skeleton. |

### Two review crons

Cron entrypoints live in `crons/` and are installed into the user's crontab by `scripts/install-crons.sh`.

| Cron | Schedule | What |
|---|---|---|
| `daily-review.sh` | 06:00 daily | Fires the `daily-auditor` subagent across every project in `~/.claude/state/audited-projects.json`. Writes per-project reports + cross-project summary. |
| `weekly-audit.sh` | 07:00 Monday | Same shape, drives the `weekly-audit` skill. ISO-week dating (`YYYY-Www`) so December rollovers don't misfile. |

Both scripts honor `--dry-run` for smoke testing and short-circuit before the `claude` CLI check so they're testable in CI environments without it installed.

## How it works

Three layers, three scopes:

```
┌────────────────────────────────────────────────────────────────┐
│  GLOBAL — ~/.claude/  (every session, any CWD)                 │
│  • skills/  ← symlinks to ~/.claude-bootstrap/skills/          │
│  • agents/  ← symlinks to ~/.claude-bootstrap/agents/          │
│  • settings.json hooks ← merged from hooks/MANIFEST.yaml       │
│  • state/, reports/, forensics/                                │
└────────────────────────────────────────────────────────────────┘
                              │
┌────────────────────────────────────────────────────────────────┐
│  PER-PROJECT — <project-root>  (sessions in that CWD only)     │
│  • MISTAKES.md, DEFINITION-OF-DONE.md (injected every turn)    │
│  • SESSION-STATE.md (injected; staleness-warned)               │
│  • RISKY-PATHS.md, BORING.md                                   │
│  • CLAUDE-ADDENDUM (appended into CLAUDE.md)                   │
│  • .github/pull_request_template.md, docs/adr/                 │
└────────────────────────────────────────────────────────────────┘
                              │
┌────────────────────────────────────────────────────────────────┐
│  CRON — ~/.claude/reports/  (off-session, independent runs)    │
│  • daily-summary-YYYY-MM-DD.md                                 │
│  • weekly-summary-YYYY-Www.md                                  │
└────────────────────────────────────────────────────────────────┘
```

Skills and agents are **symlinked** (not copied), so `git pull` in this repo updates the live install. Templates are **copied** so each project owns its institutional memory independently.

Hooks fire from `~/.claude/settings.json` and apply to every Claude Code session, in every CWD, regardless of project layer install state.

## Customization

### Per-project risk surface

The default `RISKY-PATHS.md` covers obvious-to-everyone paths (`**/*auth*/**`, `**/middleware.{ts,js}`, `**/migrations/**/*.sql`, etc.). After running `install-project.sh`, edit the project's `RISKY-PATHS.md` to add your stack's specific risk surface — payment-processing modules, RLS policies, anything tenant-scoped.

### Per-project addendum to CLAUDE.md

`install-project.sh` appends `templates/CLAUDE-ADDENDUM.md` to your project's `CLAUDE.md` via a marker string. Edit the existing `CLAUDE.md` content above the addendum block freely; the addendum is managed by the bootstrap and re-runs are idempotent.

### Adding your own skills or agents

Drop a `skills/<your-name>/SKILL.md` or `agents/<your-name>.md` in this repo with the standard frontmatter:

```yaml
---
name: your-name
description: when to use this skill
---
```

Re-run `./bootstrap.sh`. The new symlinks land alongside the bundled ones. `~/.claude/skills/<name>` is preserved if it already exists as a real directory (your hand-curated content wins).

### Adding your own hooks

Add the script to `hooks/` and register it in `hooks/MANIFEST.yaml` with the right event + matcher. Re-run `./bootstrap.sh` (or `./scripts/install-hooks.sh` directly). The merger is idempotent and won't duplicate entries on subsequent runs.

## Uninstall

The global layer:

```bash
# Remove skill / agent symlinks
rm ~/.claude/skills/{pre-flight-checklist,definition-of-done,bug-postmortem,premortem,session-debrief,daily-review,weekly-audit}
rm ~/.claude/agents/{code-reviewer,devils-advocate,task-debriefer,daily-auditor}.md

# Remove the hook entries from settings.json (manually edit, or restore from backup)
# bootstrap.sh creates ~/.claude/settings.json.backup-pre-bootstrap-YYYY-MM-DD on first run.
cp ~/.claude/settings.json.backup-pre-bootstrap-YYYY-MM-DD ~/.claude/settings.json

# Remove cron entries
crontab -l | grep -v "claude-bootstrap" | crontab -
```

The per-project layer: delete the templates from each project repo. The CLAUDE-ADDENDUM block can be removed from `CLAUDE.md` by deleting everything from the marker line onward.

## Updating

```bash
cd ~/.claude-bootstrap
make update    # git pull --rebase && ./bootstrap.sh
```

Symlinks transparently pick up skill / agent updates. Hooks are re-merged. Crons are re-checked for idempotency. The per-project templates are NOT re-pushed — they're owned by each project once installed.

## Development

```bash
make test      # bats suite (135 tests on Phase 6 cut)
make ci        # CI alias
```

Tests are bats-based (vendored as a git submodule at `tests/bats/`). The CI workflow at `.github/workflows/bats.yml` runs the suite on every push.

### Test conventions

- Every artifact category has its own bats file (`tests/skill-files-exist.bats`, `tests/agents-files-exist.bats`, `tests/templates-files-exist.bats`, etc.).
- Repo-root resolution uses `REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"` for portability across clone locations.
- Anything that would mutate user-global state in normal use has a test seam: `CLAUDE_CRONTAB_FILE` for crontab, `HOME=$(mktemp -d)` for `~/.claude`. Tests are hermetic — running `make test` never touches your real crontab or settings.

### Adding a new artifact

1. Drop the file under the right top-level directory (`skills/`, `agents/`, `templates/`, `hooks/`, `crons/`, `scripts/`).
2. Extend the relevant existing `tests/*-files-exist.bats` with a new `@test` block.
3. For hooks, register in `hooks/MANIFEST.yaml`. For skills/agents, ensure the YAML frontmatter is valid.
4. `make test` should be green before you commit.

## Repository layout

```
.
├── bootstrap.sh              # global installer (symlinks + hook merge + cron install)
├── install-project.sh        # per-project installer (template drop + CLAUDE.md addendum)
├── Makefile                  # install / test / update / ci
├── hooks/                    # 7 hook scripts + MANIFEST.yaml
├── skills/                   # 7 skills (each its own SKILL.md)
├── agents/                   # 4 subagent definitions
├── templates/                # 8 per-project templates
├── crons/                    # 2 cron entrypoints
├── scripts/                  # install-hooks.sh, install-crons.sh
├── tests/                    # bats suite + vendored bats-core
└── .github/workflows/        # CI
```

## Design notes

- **Mechanical beats aspirational.** A hook that refuses a bad action is always preferable to a rule in `CLAUDE.md` that asks Claude not to take it. The hooks are the tier-1 layer; the skills are tier-3 (process), and the agents are tier-2 (adversarial verification).
- **Fail-open on hook errors, not fail-closed.** A hook that crashes on malformed JSON is worse than one that misses an edge case. Every hook script handles bad input by silently exiting 0, so a Claude Code session is never bricked by a hook bug.
- **Idempotency is non-negotiable.** Every installer (`bootstrap.sh`, `install-project.sh`, `install-hooks.sh`, `install-crons.sh`) is safe to re-run. Symlinks replace symlinks, file copies skip if present, hook entries merge by event + matcher, cron entries match by absolute path.
- **No backwards-compatibility-bridge cruft.** When a behavior changes, the change lands cleanly. The `must-read-before-edit` 60s mtime escape, for instance, is the only deliberate ergonomic concession — and it has a test pinning it.

## License

Not yet licensed. If you'd like to use this in your own work, please reach out to discuss terms — or fork and adapt. A LICENSE will land before v1.0.

## Contributing

Bug reports and PRs welcome. The TDD cadence is rigid: every artifact lands with a failing bats test first. See the test conventions section above.
