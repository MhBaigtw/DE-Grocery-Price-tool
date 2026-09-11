# AGENTS.md

Instructions for any agent picking up this repository — Codex included.

This file is a pointer. **It deliberately does not restate the project's rules.** Those live
in `CLAUDE.md` and nowhere else; a second copy would drift from the first, and the copy is
always the one someone reads.

## Before doing anything

1. **Read `docs/RESUME.md` and follow it in full.** It is the orientation procedure — what
   to read, in what order, what to verify, and what to report. Do not skim it and start.
2. **Then read `.handoff/latest_handoff.md`** for where the last session stopped. It records
   *where work stopped*, not what is true about the project. Treat it as a pointer and
   verify it.
3. **Run `git status` and every check in `docs/RESUME.md` Step 2** before touching anything.
   Uncommitted or stashed work is the most common thing a lost session leaves behind:
   describe it, never discard it to reach a clean tree.
4. **Report the state and stop.** Do not resume work until whoever is directing the project
   confirms it. This holds even when the next step looks obvious.

## The rules that apply to you

**`CLAUDE.md` is the single source.** Its locked decisions, honesty rules, file-manifest
rules and working style apply to every agent in every session, not only to Claude. Read it
first, as `docs/RESUME.md` Step 1 instructs.

Three of those rules get broken most often by an agent arriving without context, so they are
named here as pointers — the rules themselves, and their reasoning, are in `CLAUDE.md`:

- **Counts are counts.** `40 of 40 dbt tests` is a count. A phase does not have a pass rate,
  and there is no percentage for tests that do not exist.
- **Volunteer bad news** at the moment you find it, not at the end, and not only when asked.
  A weaker-than-it-looks finding, a suspicious number, an earlier decision that now looks
  wrong — say so immediately.
- **Never work around a wrong instruction.** If a brief asks for something the findings
  forbid, or an instruction is simply wrong, say so and stop. Silently routing around it
  produces work nobody can trust and a disagreement nobody can see.

`docs/phase-2-findings.md`, section "what must never be said", is binding on every phase.

## When you finish a section

Follow `CLAUDE.md`, "Context and handoff". In short: commit, and rewrite
`.handoff/latest_handoff.md` in full from `.handoff/context_template.md` at the same time —
while context is plentiful, not when it is running out.
