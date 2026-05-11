# claude-forge

A set of guardrails, checklists, and reviewers that make [Claude Code](https://claude.com/claude-code) more reliable. Install once, and every Claude Code session on your machine inherits the protections.

## What this is, in plain language

Claude Code is great at writing code, but it has predictable failure patterns: it claims tasks are done before actually running the tests, edits files without reading them first, jumps straight to typing without orienting itself, forgets context between sessions, and quietly defers work without flagging it. You can put rules in a `CLAUDE.md` file asking it not to do these things, but a rule that lives in a markdown file is easy to drift away from.

This repo takes a different approach. Instead of asking Claude nicely, it installs **hooks** — small shell scripts that run automatically at specific moments in a Claude Code session. Some of these hooks **refuse to let Claude do certain things** (like editing a file it hasn't read, or committing directly to `main`). Others **inject context** into Claude's view at every prompt, so important information is never out of sight. There are also **skills** (short procedures Claude follows for specific situations), **subagents** (independent reviewers that audit Claude's work), and **templates** (project-specific files like `MISTAKES.md` that accumulate over time and remind Claude of past errors).

It's three layers:

1. **Global layer** — installs into `~/.claude/` and applies to every Claude Code session you ever run, in any project.
2. **Per-project layer** — drops template files into a specific repo (`MISTAKES.md`, `SESSION-STATE.md`, etc.) that Claude reads at every turn while working in that project.
3. **Background reviews** — two scheduled jobs (one daily, one weekly) that audit your projects and surface concerning patterns.

## Who this is for

People who use Claude Code daily and have been bitten by it making confident-sounding mistakes. If you've ever caught Claude:

- Saying "all tests pass!" without actually running the tests
- Editing a file it never opened, based on what it thought the file said
- Pushing changes directly to `main` when you wanted a feature branch
- Forgetting half-way through what you were working on
- Re-introducing a bug you fixed last week

…then this is for you. The hooks make those specific mistakes either impossible (refused at the system level) or much more visible (a banner in Claude's context every prompt).

## Quick start

Open a terminal. Run these commands one at a time:

```bash
# 1. Clone the repo with its test framework
git clone --recurse-submodules https://github.com/<your-fork-or-the-original>/claude-forge.git ~/.claude-forge

# 2. Move into it
cd ~/.claude-forge

# 3. Run the test suite to confirm everything works on your machine
make test

# 4. Install the global layer (skills, agents, hooks)
./bootstrap.sh

# 5. For each project you want to harden, install the per-project layer
./install-project.sh ~/path/to/your/project
```

Now **restart Claude Code**. The next session you open will see all the new skills, subagents, and hooks. If you open Claude Code inside one of the projects you ran `install-project.sh` against, you'll also see the per-project templates inject themselves into every prompt.

That's it for setup. The rest of this README explains what each piece does and how to customize it.

## What you get, at a glance

- **7 hooks** that block bad actions or inject useful context every prompt
- **7 skills** for common moments (starting a task, finishing a task, catching a bug, ending a session, etc.)
- **4 subagents** that act as independent reviewers
- **8 per-project templates** that hold institutional memory for each repo
- **2 scheduled reviews** that run daily and weekly in the background
- **2 installer scripts** that wire everything up idempotently (safe to re-run)
- **141 automated tests** covering every component, run in CI on every push

The rest of this section explains each piece. Skim it, jump to what looks useful, or read all the way through.

---

## The seven hooks

Hooks are shell scripts that run automatically at specific moments. Claude Code has a few "events" it lets hooks attach to: before a tool call (`PreToolUse`), after a tool call (`PostToolUse`), when you submit a prompt (`UserPromptSubmit`), and when a turn finishes (`Stop`). The hooks below each attach to one of those.

When `./bootstrap.sh` runs, it merges these hook registrations into your `~/.claude/settings.json` file. The merge is careful: it preserves any hooks you already have, never duplicates entries on re-run, and writes atomically so a power-loss mid-install can't corrupt your settings.

### 1. `must-read-before-edit.sh`

**What it does:** Refuses to let Claude edit a file it hasn't opened and read in the current session. If Claude tries to make an edit blind, the action is blocked and Claude has to read the file first.

**Why it exists:** Claude sometimes edits files based on what it thinks the contents are, rather than what they actually are. The bug pattern is: Claude reads file A, infers what file B probably looks like, edits B based on the inference, and corrupts it. This hook makes that impossible. Every edit requires a prior read.

**The 60-second escape:** If Claude creates a brand-new file with `Write`, it can immediately edit that file without re-reading. That's because the file's modification time is within the last 60 seconds, so the hook assumes Claude already knows what's in it. (The user can also override with `CLAUDE_BYPASS_READ_CHECK=1` in extreme situations, but you almost never need to.)

**When it fires:** On every attempted `Edit` tool call.

### 2. `log-read-paths.sh`

**What it does:** Every time Claude reads a file, this hook quietly appends the file path to a log at `~/.claude/state/reads.log`. The list is what `must-read-before-edit.sh` checks against.

**Why it exists:** Without this, the read-before-edit rule would have no way to know what Claude has actually read. The two hooks work together — this one writes the log, the other one checks the log.

**When it fires:** After every `Read` tool call.

### 3. `kill-switch.sh`

**What it does:** If a special file exists at `~/.claude/PAUSE_AND_REVIEW`, this hook blocks every tool call Claude tries to make. If you've written a reason into the file (`echo "stop and let me review" > ~/.claude/PAUSE_AND_REVIEW`), the reason is shown to Claude in the block message. To resume, delete the file.

**Why it exists:** Sometimes you want Claude to **stop immediately** mid-session — maybe it's about to do something destructive, or you spotted a misunderstanding and want to redirect before it cascades. Just `touch ~/.claude/PAUSE_AND_REVIEW` from any other terminal and Claude can't do anything until you delete the file.

**When it fires:** Before every single tool call, regardless of which tool.

### 4. `inject-mistakes-and-dod.sh`

**What it does:** Every time you submit a prompt to Claude, this hook runs first. It looks for two files in the current project directory: `MISTAKES.md` (your project's log of past errors) and `DEFINITION-OF-DONE.md` (your project's "what counts as actually finished" criteria). If either exists, the hook injects it into Claude's view for that turn — Claude sees them before responding.

**Why it exists:** Memory is unreliable in long sessions. By the time you're 4 hours in, Claude has forgotten the bug it caught at hour 1. Auto-injecting the last 10 `MISTAKES.md` entries on every prompt means past errors stay in front of Claude's eyes and don't have to be remembered.

**Last 10 entries, not the whole file:** As the MISTAKES log grows, only the most recent 10 are injected to keep Claude's context window manageable. The full file is still there for reference.

**When it fires:** Every time you hit Enter on a prompt.

### 5. `inject-session-state.sh`

**What it does:** Similar idea to `inject-mistakes-and-dod.sh`, but for a different file: `SESSION-STATE.md`. This file tracks what you're currently working on, what's queued next, and which plan you're executing. The hook injects the "In Progress" / "Next Up" / "Active Plan" sections every prompt.

**The staleness warning:** If `SESSION-STATE.md` hasn't been touched in more than 24 hours, the hook adds a warning to Claude's context — basically: "Heads up, this state file is a day old, double-check it's still accurate before resuming."

**Why it exists:** When you come back to a project after a few days, both you and Claude tend to lose the thread. SESSION-STATE.md is the breadcrumb trail. The hook ensures Claude reads it every single turn, not just at the start of the session.

**When it fires:** Every time you hit Enter on a prompt.

### 6. `block-direct-main-commit.sh`

**What it does:** Refuses any `git commit` command run on the `main` or `master` branch. To override, you can either include the literal string `ALLOW-MAIN-COMMIT:` in the commit message itself (intended as a deliberate, in-message acknowledgment), or set `CLAUDE_ALLOW_MAIN=1` in your environment.

**Why it exists:** Direct commits to `main` are how the worst regressions ship. Forcing a feature branch (`git checkout -b feat/something`) before any commit means there's always a chance to review the diff in a pull request before it hits production.

**Smart edge cases:** The check carefully avoids false positives on commands like `git commit-tree` or `git commit-graph` (different Git plumbing commands that happen to start with "git commit"). It also doesn't fire when you're not in a Git repo, or when you're on a detached HEAD.

**When it fires:** Before any `Bash` tool call that includes the words `git commit`.

### 7. `require-verification-before-done.sh`

**What it does:** When Claude finishes a turn and says something like "all done!" or "tests pass!" or "verified," this hook checks the recent conversation transcript. If it sees a "done" claim but no evidence of an actual test run, type-check, or verification command in the recent activity, it injects a reminder: "I see you're wrapping up, but I don't see verification output. Run `pnpm typecheck && pnpm test` (or your stack's equivalent) and paste the output."

**Why it exists:** The user's most common complaint about Claude was that it would confidently declare work complete without ever actually running the tests. This hook adds friction at the exact moment of false confidence.

**Important nuance:** This hook is a **nag, not a block**. It can only inject context, not refuse action. If Claude wants to say "done" anyway after seeing the warning, that's allowed — but the nudge is right there in its view.

**When it fires:** At the end of every turn (the `Stop` event).

---

## The seven skills

Skills are short, focused procedures Claude follows when invoked. Each one lives as a markdown file at `skills/<name>/SKILL.md` and gets symlinked into `~/.claude/skills/` on install. Claude can see the list at session start and chooses to invoke them when appropriate (you can also tell Claude to invoke one explicitly).

Think of skills as **checklists Claude follows when a specific situation arises**. The skills below cover the most common moments where Claude tends to slip up.

### 1. `pre-flight-checklist`

**When to use:** Before starting any non-trivial coding task — anything that touches more than two files, or any file flagged as "risky" by the project's `RISKY-PATHS.md`.

**What Claude does:** Before writing any code, Claude outputs a six-section block:
- **Files I'm about to touch** — the explicit list
- **Files I will Read first to orient** — schemas, related modules, tests Claude should read before editing anything
- **Tests that will prove this works** — what bats / unit tests Claude plans to write
- **What I'm assuming that I haven't yet verified** — every shaky assumption, surfaced explicitly
- **What could go wrong** — three specific failure modes
- **Definition of done** — an observable criterion you could verify yourself

After outputting this, Claude pauses for a brief exchange so you can redirect if the plan is off. Only then does the actual work begin.

**Why it exists:** Claude's biggest failure mode is jumping straight to tool calls before orienting. The pre-flight forces a written plan, which forces the orienting.

### 2. `definition-of-done`

**When to use:** At the end of any non-trivial task, before claiming the work is complete.

**What Claude does:** Outputs an 11-row evidence table. Each row asks a specific question: did the typecheck pass, were tests added, did the tests run green, was the diff self-reviewed, was `SESSION-STATE.md` updated, etc. Each row requires Claude to fill in YES / NO / N/A, plus the command and output excerpt that proves the YES.

If any row is NO, the task isn't done. Claude either fixes the gap or explicitly defers it (with a reason) and tells you about the gap.

**Why it exists:** "I think it works" is not the same as "I ran the tests and they pass." The table converts subjective confidence into evidence.

### 3. `bug-postmortem`

**When to use:** Whenever you catch Claude in a bug, wrong assumption, or mistake.

**What Claude does:** Produces two artifacts in a single commit:
1. **A MISTAKES.md entry** documenting what Claude assumed vs. what was actually true, how the bug manifested, the root cause in one sentence, and what would have caught it earlier.
2. **The actual guard against recurrence** — a test, lint rule, or hook that, if it had existed before the bug, would have surfaced the bug. Claude writes the guard, adds it to the suite, and confirms green.

**Why it exists:** Without a mechanical guard, the same mistake will recur. The postmortem is the discipline of converting "lesson learned" into "test that catches it next time."

### 4. `premortem`

**When to use:** At the start of any phase, or before any task estimated to take more than 4 hours.

**What Claude does:** Three sections, before any tool calls:
- **"Imagine this shipped and broke. What were the 3 most likely failure modes?"** — for each, the user-visible symptom, the root cause hypothesis, and a pre-flight defense.
- **"What would the user catch first?"** — what's the most likely thing you'd notice that's wrong.
- **"What's the cheapest reversible thing I'd do first to de-risk?"** — a small smoke test, a clarifying question, a mock before the real integration.

**Why it exists:** Premortems are cheap. A failure mode you've already imagined is much less likely to surprise you.

### 5. `session-debrief`

**When to use:** At the end of a coding session, or when you say things like "wrapping up" or "let's stop here."

**What Claude does:** Five steps:
1. Updates `SESSION-STATE.md` (bumps the date, moves items from "In Progress" to "Recently Completed," refreshes "Next Up").
2. Appends any new `MISTAKES.md` entries from things caught during the session.
3. Surfaces unmet commitments ("you said you'd come back to X — list of those").
4. Runs `git status` and a typecheck to make sure nothing is broken at HEAD.
5. Commits the state update on your current feature branch.

**Why it exists:** Without an end-of-session ritual, the next session starts from scratch and has to figure out what was happening. The debrief leaves a complete breadcrumb.

### 6. `daily-review`

**When to use:** Invoked automatically by the daily cron at 6:00 AM (see "scheduled reviews" below). Can also be invoked manually.

**What Claude does:** Outputs a markdown digest covering the last 24 hours:
- **Activity** — commits, hottest files touched, branches that saw work
- **MISTAKES.md additions** — new entries, with pattern flags if they're clustered
- **SESSION-STATE.md drift** — items that have been "In Progress" for more than 3 days
- **Unverified claims** — done-claims in the transcript with no matching test run
- **Concerning patterns** — files edited more than 3 times in 24h, test-suite shrinkage, new `TODO/FIXME/HACK` comments

Saved as `reports/daily/YYYY-MM-DD.md` in the project. Anything alarming also gets a Slack-ready summary.

**Why it exists:** Daily drift you don't notice becomes weekly chaos. The review is your background quality monitor.

### 7. `weekly-audit`

**When to use:** Invoked automatically by the weekly cron Monday at 7:00 AM. Can also be invoked manually.

**What Claude does:** A deeper review than the daily one, covering:
- **ADR drift** — for each Architecture Decision Record in `docs/adr/`, has the actual code drifted from the recorded decision?
- **Mistakes-as-tests reconciliation** — every entry in `MISTAKES.md` from the past month: does a test/lint/hook actually guard against it? Missing guards are drafted.
- **Dependency staleness** — `pnpm outdated` and `pnpm audit` flag major-version-behind packages and high/critical CVEs.
- **Model + API deprecations** — for any Anthropic model ID hardcoded in the project, checks the current model list.
- **Vendor BAA expiry** — flags contracts expiring inside 30 days.
- **CI green-bar history** — pass rate over the last 7 days; trend improving/stable/degrading?

Saved as `reports/weekly/YYYY-Www.md`.

**Why it exists:** Weekly slips become monthly disasters. The audit catches them while they're still fixable.

---

## The four reviewer subagents

Subagents are separate, focused Claude instances that Claude can dispatch when it needs a second opinion. They live as markdown files at `agents/<name>.md`, get symlinked into `~/.claude/agents/`, and Claude invokes them via its `Agent` tool.

All four subagents below use a **read-only tool allowlist** (Read, Grep, Glob, Bash). Reviewers can inspect — they can't edit. This is deliberate: a reviewer that can also write the code isn't independent.

### 1. `code-reviewer`

**When to use:** Whenever a non-trivial change is complete, especially if any of the files touched are listed in the project's `RISKY-PATHS.md`. Often called automatically by Claude after wrapping up a meaningful piece of work.

**What it does:** The reviewer gets the original task description and the diff of changed files — but **not** Claude's reasoning. It reads every line of every changed file, looks up at least one caller / test / related schema for each, scores the change on a 5-axis rubric (correctness, verification, schema/type safety, blast-radius awareness, convention match), and then has to guess where the most likely bug is — even at low confidence. Finally it returns one of:
- **APPROVE** — clean enough to merge
- **REQUEST_CHANGES** — specific issues at file:line
- **NEEDS_CONTEXT** — can't judge without more information; lists what's missing

The reviewer's instructions specifically say: false approval costs more than false rejection. It's biased toward skepticism.

**Why it exists:** Self-review is unreliable. An independent pass, blind to the author's reasoning, catches things the author rationalized away.

### 2. `devils-advocate`

**When to use:** When you're about to claim "done" on a change that touches risky paths, and you want an adversarial pass.

**What it does:** This reviewer's instructions are explicit: "Assume the change is broken. Find HOW." It's not a balanced review. It attacks specific surfaces — race conditions, boundary conditions (empty / null / unicode / very long), trust boundaries (can a tenant spoof another tenant's slug?), dependency failure modes (what if Anthropic returns 429? What if the HMAC secret is wrong?), state drift, "who else calls this?" cascades.

The output is a specific scenario where the change fails: file:line, the input that triggers it, the symptom.

**Why it exists:** The neutral `code-reviewer` is balanced. Sometimes you want the opposite — a paranoid colleague trying to break your change before production does.

### 3. `task-debriefer`

**When to use:** At the end of any non-trivial task. Can be invoked manually, or wired up to fire automatically.

**What it does:** Re-reads the user's original request word by word, identifies the explicit and implicit asks, and compares those against the diff. Flags:
- Gaps between what was asked and what was built
- Claimed verifications without evidence in the transcript ("I ran the tests" with no test output → flagged)
- Quietly-deferred work ("we'll come back to X" → flagged)
- Missing MISTAKES.md / SESSION-STATE.md updates

Returns one of: **TASK COMPLETE**, **TASK INCOMPLETE — gaps listed below**, or **TASK COMPLETE BUT FOLLOWUP REQUIRED**.

**Why it exists:** Did Claude actually solve what was asked, or what Claude thought was asked? Often there's a gap. The debriefer is the audit.

### 4. `daily-auditor`

**When to use:** Invoked automatically by the daily and weekly crons. Not typically called by hand.

**What it does:** Walks every project listed in `~/.claude/state/audited-projects.json`, runs the `daily-review` skill (or `weekly-audit`) against each, saves per-project reports, then aggregates the cross-project red flags into a single summary at `~/.claude/reports/`. Things it surfaces immediately: test-suite shrinkage, repeated mistakes in the same file, `SESSION-STATE.md` stale beyond 24h, unverified done-claims, new high/critical CVEs.

**Why it exists:** When you have multiple active projects, you want one summary, not five separate reports. The auditor produces the rollup.

---

## The eight per-project templates

These are template files that get dropped into each project when you run `./install-project.sh <project>`. The installer never overwrites existing files — if your project already has a `MISTAKES.md`, that one wins.

### 1. `MISTAKES.md`

**Lands at:** `<project>/MISTAKES.md`

**What it is:** Your project's living log of past errors. Every time Claude makes a wrong assumption or you catch a bug, an entry gets appended via the `bug-postmortem` skill. Each entry records what was assumed, what was actually true, how the bug manifested, the root cause, and what would have caught it earlier.

**Who reads it:** `inject-mistakes-and-dod.sh` auto-injects the last 10 entries into Claude's context every prompt. So Claude is never far from a reminder of the most recent things that went wrong.

**Who writes it:** Claude, via the `bug-postmortem` skill, with the corresponding regression-guard test in the same commit.

### 2. `DEFINITION-OF-DONE.md`

**Lands at:** `<project>/DEFINITION-OF-DONE.md`

**What it is:** Your project's explicit "what counts as actually done" criteria. The default template lists 12 rows: typecheck green, tests added, tests pass, UI screenshot if applicable, migration applied to a real DB if applicable, route hit with a real HTTP request, diff self-reviewed, SESSION-STATE updated, etc.

You should edit this for your project — add or remove rows that fit your stack. The default is a good starting point.

**Who reads it:** Also auto-injected into Claude's context every prompt by `inject-mistakes-and-dod.sh`. Claude sees the bar at every turn.

**Who writes it:** You, mostly. Update it as your project's "done" criteria evolve.

### 3. `RISKY-PATHS.md`

**Lands at:** `<project>/RISKY-PATHS.md`

**What it is:** A list of file path patterns (globs) that require extra ceremony. The defaults cover obvious ones — anything matching `**/*auth*/**`, `**/middleware.{ts,js}`, `**/migrations/**/*.sql`, `**/*secret*`, `**/api/**`, `.github/workflows/**`, `package.json`, `tsconfig.json`, `.env.example`.

When Claude touches a risky path, it's expected to:
- Read the file first (already enforced by the hook)
- Run the pre-flight checklist
- Invoke the `code-reviewer` subagent before claiming done
- Fill the `DEFINITION-OF-DONE.md` table completely

**Customize per project:** Add your project's specific risk surface — payment processing modules, anything touching customer-facing email, RLS policies, anything tenant-scoped.

### 4. `BORING.md`

**Lands at:** `<project>/BORING.md`

**What it is:** The inverse of `RISKY-PATHS.md`. While risky paths require *extra ceremony*, boring paths require *no novelty*. These are problem areas where the established, well-tested pattern is almost always right and a clever new pattern is almost always wrong.

Defaults: authentication (use the framework's auth, not custom code), HMAC verification (use the standard library's `timingSafeEqual`, never hand-roll a string compare), SQL migrations (plain SQL with `IF NOT EXISTS`), date handling (the platform's date library, not string parsing), JSON parsing (`try/catch` with explicit error path), environment variable validation (Zod at process start).

If Claude reaches for something novel in any of these areas, it's expected to justify it explicitly.

### 5. `SESSION-STATE.md`

**Lands at:** `<project>/SESSION-STATE.md`

**What it is:** The breadcrumb file. Six sections: Last Updated (date), Recently Completed, In Progress, Next Up, Active Plan, Key Context.

**Who reads it:** `inject-session-state.sh` injects the **In Progress**, **Next Up**, and **Active Plan** sections into every prompt. The full file is read by Claude at session start.

**Who writes it:** Claude updates it via the `session-debrief` skill at session end. You can also edit it directly between sessions.

**The staleness warning:** If the file's modification time is more than 24h old, the hook adds a "this is stale, refresh it" warning to Claude's context. This catches the case where you come back to a project after a few days and the state is from the old session.

### 6. `CLAUDE-ADDENDUM.md` (appended to `CLAUDE.md`)

**Lands as:** an appended block in `<project>/CLAUDE.md`. If your project doesn't have a `CLAUDE.md`, one is created with just the addendum content.

**What it is:** A block that tells Claude about the bootstrap conventions in this specific project. It lists the required reading at session start, the trigger conditions for each skill, the hook behaviors to expect, and the refusal-mode policy ("when a hook blocks an action, don't retry it — read the rejection, address the gap, then retry, or surface the gap to the user").

**Idempotency marker:** The addendum starts with a unique marker string. Running `install-project.sh` again checks for the marker first — if present, the addendum is skipped (no duplicate). Edit your project's `CLAUDE.md` content above the addendum block freely; the bootstrap won't touch it.

### 7. `.github/pull_request_template.md`

**Lands at:** `<project>/.github/pull_request_template.md`

**What it is:** A PR template GitHub auto-uses when you open a pull request. Four sections: what changed (bullets), why (link to issue or one-sentence motivation), an inline copy of the Definition-of-Done table, and a "risk + rollback plan" section.

**Why a separate template:** The DoD table the user sees in their PR description is exactly the same table Claude is filling out at task end. That alignment means the PR review is a check against the same bar Claude was just held to.

### 8. `docs/adr/0000-template.md`

**Lands at:** `<project>/docs/adr/0000-template.md`

**What it is:** An Architecture Decision Record skeleton. ADRs are short markdown docs (typically 1-2 pages) that record an architectural decision: the context (what problem, what forces, what deadline), the actual decision, the alternatives considered (with rejection reasons), the consequences (positive, negative, reversible?), and any followups (tasks unblocked, tasks blocked).

**Why ADRs:** Six months from now, no one remembers why you chose Approach A over Approach B. ADRs are how you preserve the reasoning.

**The weekly audit checks these:** The `weekly-audit` skill includes a section that checks whether the code has drifted from each recorded ADR. Decisions that no longer match reality get flagged.

---

## The two scheduled reviews

Two scripts in `crons/` are installed into your system's crontab by `scripts/install-crons.sh`. They run on a schedule with no user in the loop.

### 1. `daily-review.sh` — runs every day at 6:00 AM

**What it does:** Fires the `daily-auditor` subagent. The auditor walks every project in `~/.claude/state/audited-projects.json` (which gets populated by `install-project.sh`), runs the `daily-review` skill against each, and saves:
- A per-project report at `<project>/reports/daily/YYYY-MM-DD.md`
- A cross-project summary at `~/.claude/reports/daily-summary-YYYY-MM-DD.md`

**What you do with the report:** Read it over coffee. The summary surfaces anything alarming. Most days it'll be a small markdown file noting "no concerning patterns." Occasionally it'll catch something like "the test suite shrunk by 8 tests overnight — investigate."

**Test seam:** Pass `--dry-run` and the script short-circuits before invoking Claude, just confirming where it *would* write. Useful for verifying the cron is wired without burning Claude API tokens.

### 2. `weekly-audit.sh` — runs every Monday at 7:00 AM

**What it does:** Same shape, but drives the `weekly-audit` skill (deeper-cadence audit covering ADR drift, dependency staleness, model deprecations, BAA expiry, etc.). Saves per-project reports at `<project>/reports/weekly/YYYY-Www.md` and a summary at `~/.claude/reports/weekly-summary-YYYY-Www.md`.

**ISO-week dating:** The week is encoded as `YYYY-Www` (e.g. `2026-W19`). This correctly handles the December rollover edge case where calendar year and ISO year disagree.

### Where the cron entries live

`scripts/install-crons.sh` adds two lines to your user crontab. You can inspect them with `crontab -l`. They look like:

```
0 6 * * * /Users/you/.claude-forge/crons/daily-review.sh > /tmp/claude-daily-review.log 2>&1  # claude-forge
0 7 * * 1 /Users/you/.claude-forge/crons/weekly-audit.sh > /tmp/claude-weekly-audit.log 2>&1  # claude-forge
```

The install is idempotent — re-running never duplicates entries. If you move or rename the bootstrap checkout, run `./bootstrap.sh` again and the crontab paths update.

---

## How it all fits together

```
┌──────────────────────────────────────────────────────────────────┐
│  GLOBAL — ~/.claude/                                             │
│  Every Claude Code session, every project, every CWD.            │
│                                                                  │
│  ~/.claude/skills/      ← symlinks to ~/.claude-forge/skills │
│  ~/.claude/agents/      ← symlinks to ~/.claude-forge/agents │
│  ~/.claude/settings.json hooks ← merged in by install-hooks.sh   │
│  ~/.claude/state/, reports/, forensics/                          │
└──────────────────────────────────────────────────────────────────┘
                                │
┌──────────────────────────────────────────────────────────────────┐
│  PER-PROJECT — <your-project-root>/                              │
│  Only when Claude Code is running in that directory.             │
│                                                                  │
│  MISTAKES.md, DEFINITION-OF-DONE.md  ← injected every prompt     │
│  SESSION-STATE.md                    ← injected, staleness-warn  │
│  RISKY-PATHS.md, BORING.md           ← read by Claude as needed  │
│  CLAUDE.md (with addendum)           ← read at session start     │
│  .github/pull_request_template.md, docs/adr/                     │
└──────────────────────────────────────────────────────────────────┘
                                │
┌──────────────────────────────────────────────────────────────────┐
│  BACKGROUND — runs from cron, no human in the loop               │
│                                                                  │
│  06:00 daily    → daily-review.sh → per-project + cross-project  │
│  07:00 Mon      → weekly-audit.sh → deeper audit                 │
│  Both write to ~/.claude/reports/                                │
└──────────────────────────────────────────────────────────────────┘
```

Skills and agents are **symlinked** (not copied), so when you `git pull` in `~/.claude-forge/`, your installed skills and agents update automatically. Templates are **copied** so each project owns its own institutional memory independently.

---

## Step-by-step install

This is the longer version of the Quick Start at the top.

### Prerequisites

You'll need `git`, `bash`, `jq`, and `make` available on your PATH. macOS comes with all of these except `jq` (install with `brew install jq`). Linux package managers all have them.

You'll also need Claude Code itself installed and working. If `claude --version` runs in your terminal, you're good.

### 1. Clone the repo

```bash
git clone --recurse-submodules https://github.com/<your-fork>/claude-forge.git ~/.claude-forge
```

The `--recurse-submodules` flag pulls in `bats-core` (the test framework) as a vendored git submodule. Without it, the test suite won't run.

### 2. Verify the tests pass

```bash
cd ~/.claude-forge
make test
```

You should see 141 tests, all green. If any fail, **don't proceed with the install** — open an issue, or check whether you missed a dependency.

### 3. Install the global layer

```bash
./bootstrap.sh
```

This does five things:
1. Creates the directories `~/.claude/skills/`, `~/.claude/agents/`, `~/.claude/state/`, `~/.claude/forensics/`, `~/.claude/reports/` if they don't exist
2. Symlinks each skill from `~/.claude-forge/skills/` into `~/.claude/skills/`
3. Symlinks each agent from `~/.claude-forge/agents/` into `~/.claude/agents/`
4. Runs `scripts/install-hooks.sh` to merge the 7 hooks into `~/.claude/settings.json` (idempotent, preserves any hooks you already have)
5. Runs `scripts/install-crons.sh` to add the daily and weekly review entries to your crontab

You'll see a summary at the end:

```
claude-forge installed.
  skills: 7
  agents: 4
  hooks merged into /Users/you/.claude/settings.json
crontab updated
```

### 4. Install the per-project layer for one or more projects

```bash
~/.claude-forge/install-project.sh ~/path/to/your/project
```

This drops 8 template files into the project (each with the same "skip if file already exists" idempotency), appends the CLAUDE-ADDENDUM block to your existing `CLAUDE.md` (or creates one if none exists), and registers the project in `~/.claude/state/audited-projects.json` so the daily and weekly crons will pick it up.

Run this once per project you want to harden.

### 5. Restart Claude Code

Close the Claude Code window or session, and open a new one inside one of your hardened projects. The new session will see all the skills and subagents in its available-skills list, and the per-project files will be auto-injected starting from your very first prompt.

---

## How to use it day to day

Once installed, the system mostly stays out of your way until it doesn't. Here's what you'll actually notice:

**At session start:** Claude reads your `SESSION-STATE.md` and `CLAUDE.md` (with addendum). It knows what you were last working on.

**At every prompt:** Claude sees your recent `MISTAKES.md` entries and your `DEFINITION-OF-DONE.md` table at the top of its context. If `SESSION-STATE.md` is stale, there's a warning.

**Before any non-trivial change:** Claude is expected to output the pre-flight checklist. If it dives straight into edits, prompt it: "Run the pre-flight first."

**When you catch a bug:** Tell Claude. It should invoke the `bug-postmortem` skill — appending a MISTAKES entry AND writing the test that would have caught it, then committing both together.

**Before claiming done:** Claude should fill the DoD table with evidence. If you see "all done!" without the table, the `require-verification-before-done.sh` hook should have nagged Claude already; if it didn't, prompt explicitly: "fill the definition-of-done."

**At session end:** Tell Claude "we're wrapping up" or invoke the `session-debrief` skill. It'll update SESSION-STATE.md and commit.

**Background:** The daily and weekly reports show up in `~/.claude/reports/`. Read them with your morning coffee.

---

## Customization

### Editing `RISKY-PATHS.md` for your project's risk surface

The default `RISKY-PATHS.md` is generic. Edit your project's copy to add the paths that matter for your stack. Examples:

```markdown
## Project-specific additions

- `app/api/billing/**` — anything touching payment flow
- `prisma/migrations/**` — schema changes
- `lib/rate-limiter.ts` — quota enforcement
- `**/.env.production` — never modify this from a Claude session
```

After you edit, the next session Claude opens in this project will see the change at session start. Claude is expected to treat any file matching these patterns with extra ceremony.

### Adding your own skills

Create a new directory and file at `~/.claude-forge/skills/<your-skill-name>/SKILL.md`. The file needs YAML frontmatter:

```markdown
---
name: your-skill-name
description: When to use this skill (one sentence).
---

# Your skill name

The actual procedure Claude should follow goes here. Be specific. Include
sections, examples, and what output Claude should produce when invoked.
```

Re-run `~/.claude-forge/bootstrap.sh` to symlink the new skill into `~/.claude/skills/`. The next Claude Code session will see it.

### Adding your own subagents

Same idea, but at `~/.claude-forge/agents/<your-agent-name>.md`. The frontmatter requires a third field — `tools` — that lists what tools the agent is allowed to use:

```markdown
---
name: your-agent-name
description: When to invoke this subagent.
tools: [Read, Grep, Glob, Bash]
---

You are a [persona]. When invoked, you receive [inputs]. Your job is to [task].

[detailed instructions...]
```

Keep reviewer agents read-only (no `Edit`, no `Write`) — that's what makes them independent.

### Adding your own hooks

Drop the hook script in `hooks/`, make it executable (`chmod +x`), then register it in `hooks/MANIFEST.yaml` with the correct event + matcher. Example:

```yaml
- event: PreToolUse
  matcher: Bash
  command: my-custom-bash-guard.sh
```

Re-run `./bootstrap.sh` (or `./scripts/install-hooks.sh` directly). The merger is idempotent — it won't duplicate.

---

## Uninstall

### Removing the global layer

```bash
# Symlinks for skills and agents
rm ~/.claude/skills/{pre-flight-checklist,definition-of-done,bug-postmortem,premortem,session-debrief,daily-review,weekly-audit}
rm ~/.claude/agents/{code-reviewer,devils-advocate,task-debriefer,daily-auditor}.md

# Hooks: restore from the backup that bootstrap.sh created on first run
# (look for ~/.claude/settings.json.backup-pre-bootstrap-YYYY-MM-DD)
ls ~/.claude/settings.json.backup-pre-bootstrap-*
cp ~/.claude/settings.json.backup-pre-bootstrap-YYYY-MM-DD ~/.claude/settings.json

# Cron entries
crontab -l | grep -v "claude-forge" | crontab -
```

### Removing the per-project layer from a project

```bash
cd ~/path/to/your/project
rm MISTAKES.md DEFINITION-OF-DONE.md RISKY-PATHS.md BORING.md SESSION-STATE.md
rm .github/pull_request_template.md docs/adr/0000-template.md

# CLAUDE.md addendum: open in your editor and delete everything from the
# "# Bootstrap addendum" line onward. (Your project-owned content above the
# addendum stays.)
```

### Removing the project from cron audits

Edit `~/.claude/state/audited-projects.json` and remove the entry for the project. Or, to drop all audits, just delete the file.

---

## Updating

When new commits land in the bootstrap repo:

```bash
cd ~/.claude-forge
make update    # git pull --rebase && ./bootstrap.sh
```

Symlinks transparently pick up skill and agent updates (because they point at the repo, not at copies). Hook entries are re-merged for idempotency. Cron entries are re-checked. **Templates in your existing projects are not re-pushed** — they're owned by each project once installed.

To deliberately re-install a project's templates after a bootstrap update (e.g., to pick up a new default `RISKY-PATHS.md`), back up your customizations first, then re-run `install-project.sh`. The script will skip files that already exist, so you'd want to delete the specific ones you want refreshed before re-running.

---

## For developers and contributors

### Running the test suite

```bash
make test
```

Or, equivalently:

```bash
./tests/bats/bin/bats tests/
```

You should see 141 tests across these files:
- `tests/smoke.bats` — repo skeleton exists
- `tests/must-read-before-edit.bats` — hook 1 behavior
- `tests/log-read-paths.bats` — hook 2 behavior
- `tests/kill-switch.bats` — hook 3 behavior
- `tests/inject-mistakes-and-dod.bats` — hook 4 behavior
- `tests/inject-session-state.bats` — hook 5 behavior
- `tests/block-direct-main-commit.bats` — hook 6 behavior
- `tests/require-verification-before-done.bats` — hook 7 behavior
- `tests/install-hooks.bats` — hook composer behavior
- `tests/install-crons.bats` — cron installer behavior
- `tests/skill-files-exist.bats` — every skill present
- `tests/agents-files-exist.bats` — every agent present
- `tests/templates-files-exist.bats` — every template present
- `tests/bootstrap.bats` — full bootstrap.sh
- `tests/install-project.bats` — full install-project.sh
- `tests/makefile.bats` — Makefile targets
- `tests/daily-review.bats` — daily cron entry
- `tests/weekly-audit.bats` — weekly cron entry
- `tests/readme.bats` — this README's reader-completeness guard

### Test conventions

- Tests resolve the repo root with `REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"`, not a hardcoded path. So tests work no matter where the user clones to.
- Anything that would mutate user-global state has a test seam. `CLAUDE_CRONTAB_FILE` lets the bats suite test the cron installer against a temp file instead of the real crontab. `HOME=$(mktemp -d)` lets the bats suite test the bootstrap installer against a temp directory instead of the real `~/.claude/`. **Running `make test` should never touch your real crontab or your real `~/.claude/`.**

### Adding a new artifact

1. Drop the file under the right top-level directory (`skills/`, `agents/`, `templates/`, `hooks/`, `crons/`, `scripts/`).
2. Extend the relevant existing `tests/*-files-exist.bats` with a new `@test` block — or add a new behavior-specific bats file.
3. For hooks, register the script in `hooks/MANIFEST.yaml`. For skills and agents, ensure the YAML frontmatter is valid.
4. Run `make test`. It should be green before you commit.

### CI

`.github/workflows/bats.yml` runs the full test suite on every push and pull request. The build is green-bar gated — no merge without passing tests.

---

## Repository layout

```
.
├── bootstrap.sh              # Global installer
├── install-project.sh        # Per-project installer
├── Makefile                  # install / test / update / ci targets
├── hooks/                    # 7 hook scripts + MANIFEST.yaml
├── skills/                   # 7 skills, each its own SKILL.md
├── agents/                   # 4 subagent definitions
├── templates/                # 8 per-project templates
├── crons/                    # 2 cron entrypoints
├── scripts/                  # install-hooks.sh, install-crons.sh
├── tests/                    # bats suite + vendored bats-core
└── .github/workflows/        # CI
```

---

## Design notes

A few principles drove the design choices throughout.

**Mechanical beats aspirational.** A hook that refuses an action is always more reliable than a rule in `CLAUDE.md` asking Claude not to take it. The hooks are tier-1 (refusal-blocking). The auto-injection hooks (`inject-mistakes-and-dod`, `inject-session-state`) are tier-2 (always-visible context). The skills, templates, and CLAUDE.md addendum are tier-3 (procedural / soft). When a behavior can be enforced mechanically, it is.

**Fail-open on hook errors, not fail-closed.** A hook that crashes on malformed JSON is worse than one that misses an edge case — a crashing hook can brick the session. Every hook handles bad input by silently exiting 0. You may occasionally see a hook miss a case it should have caught; you'll never see a hook lock you out of Claude Code.

**Idempotency is non-negotiable.** Every installer (`bootstrap.sh`, `install-project.sh`, `install-hooks.sh`, `install-crons.sh`) is safe to re-run. Re-running is in fact how you update.

**No backwards-compatibility cruft.** When a behavior changes in a new version, the change lands cleanly. The 60-second mtime escape in `must-read-before-edit` is the only deliberate ergonomic concession — and it has a test pinning it.

**Tests own the invariants.** When the code-reviewer agent caught a missing `SESSION-STATE.md` template during initial development, the fix wasn't just to add the template — it was to add a test asserting it ships with the three section headers the inject-session-state hook greps for. Future drift would surface immediately.

---

## License

Not yet licensed. If you'd like to use this in your own work, please reach out to discuss terms, or fork and adapt. A LICENSE will land before v1.0.

## Contributing

Bug reports and pull requests welcome. The TDD cadence is rigid: every artifact lands with a failing bats test first, and the test stays in the suite to guard against regression. See the "Adding a new artifact" section above for the workflow.
