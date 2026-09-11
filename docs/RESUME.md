# RESUME

**Read this first if you are picking up this project without prior context** — a new
session, a different agent, or a human returning after a break.

The repository is the source of truth. Not a summary, not a handoff note, not anything
another model said. If a document and the repository disagree, the repository wins and
the document gets fixed.

---

## Step 1 — Read, in this order

    CLAUDE.md                     locked decisions, honesty rules, licence terms
    docs/FILES.md                 what every file is, and the reading order
    docs/phase-2-findings.md      the results, the withdrawals, what must never be said
    .handoff/latest_handoff.md    what the last session was doing, if it exists

Then the brief for whatever phase is current.

`.handoff/latest_handoff.md` tells you where work stopped. It does **not** tell you what
is true about the project — the docs above do. Treat it as a pointer, not as evidence.

## Step 2 — Verify, do not assume

Run every check before touching anything:

    git log --oneline -15
    git status
    git branch -a
    python scripts/check_manifest.py
    python scripts/check_schema.py
    python scripts/check_layering.py
    python scripts/verify_reproducible.py

Plus the test suites and the determinism lint.

Uncommitted or stashed work is the most common thing a lost session leaves behind.
Describe it before doing anything with it. Never discard it to get to a clean tree.

## Step 3 — Report before working

State, in the reply:

- The last commit, and whether the tree is clean
- Any uncommitted or stashed work, described
- Every check result, as counts — files **and** entries for the manifest, never one
- Which phase and section is current, per the briefs and the handoff note
- **Anything that contradicts what the handoff note or the docs claim**

Then stop. Do not begin work until the state is confirmed by whoever is directing the
project.

## Step 4 — Working rules

These apply to any agent, in any session:

- Work section by section. Finish, report, wait. Never run ahead into the next section.
- **Commit at the end of every completed section, before reporting.** Uncommitted work
  is the only thing a lost session actually destroys.
- Update `.handoff/latest_handoff.md` at the same time you commit — see
  `.handoff/context_template.md`. Write it while context is plentiful, not when it is
  running out.
- Report counts as counts. `40 of 40 dbt tests` is a count. There is no such thing as a
  pass rate for a phase.
- Volunteer bad news at the point you discover it, not at the end.
- If an instruction in a brief is wrong, say so and stop. Do not work around it silently.

## Stop conditions

Stop and report rather than proceeding if:

- Any check fails, or the manifest and the repository disagree
- The upstream schema has changed
- The handoff note describes a state the repository does not support
- A brief asks for something the findings forbid — `docs/phase-2-findings.md`,
  "what must never be said", is binding on every phase
