# Handoff — 2026-09-12 02:30, Claude Opus 5

> Rewritten in full at the end of every completed section, at the same time as the
> commit. Never written in a hurry at the end of a session — a note written while
> context is running out is exactly the note you cannot trust.
>
> This file records **where work stopped**. It is not a record of what is true about the
> project. Ground truth is the repository: `CLAUDE.md`, the findings docs, the briefs and
> git history. Anyone reading this reads `docs/RESUME.md` first.

## Orientation

Read `docs/RESUME.md` and follow it before doing anything. Do not treat the sections
below as verified state — verify them.

## Current phase and section

Phase 4 (the price-lookup tool). Sections 1 to 5 built; brief `docs/phase-4-brief.md`,
results `docs/phase-4-findings.md` (§1–§8).

The tool is **deployed and live on Netlify** at **https://de-grocery-project.netlify.app**,
with continuous deployment from `main` verified end to end. The only open item in the
owner's deploy sequence is the custom domain.

## Last commit

See `git log -1`. This note is committed with it. The tree was clean when written, and
`main` matched `origin/main`.

## What the last session completed

- Deploy target moved from GitHub Pages to Netlify (owner's decision). `deploy.yml` removed so
  there is one deploy path; `netlify.toml` and `scripts/netlify_build.sh` added.
- Netlify site `de-grocery-project` (site id `36972e0e-7430-455a-998a-a966c9a0a6a9`) created
  and linked by the owner running `netlify init` in a real terminal.
- **Continuous deployment proven with a real push**, not inferred: commit `2232900` triggered a
  build on Netlify's builder (it has a `build_id`), reached `ready` in production, and is the
  published deploy.
- `scripts/verify_deploy.py` passed against the live URL, including the compression check —
  Netlify serves the large JSON **brotli**, `products.json` 312 KB over the wire.
- Phone profile measured against the live CDN: FCP 1.35 s, interactive 3.99 s, search
  keystroke 68 ms, first history click 1.96 s.

## Immediate next steps

1. **Custom domain.** The owner will supply a hostname once satisfied with the
   `netlify.app` subdomain. **Do not configure a domain or CNAME before that.** On Netlify the
   domain is set in the UI (Domain management), not with a `CNAME` file — the build script
   deletes any `CNAME` from `_site` for exactly that reason. After it is set, re-run
   `verify_deploy.py` against the custom hostname, and check that the tool and the writeup
   are both reachable from the domain's landing page (owner's requirement: someone arriving
   from a resume or a post must find both without a deep link).
2. Then tell the dataset maintainer the project is published. The owner's decision is to
   publish independently and tell him afterwards.

## Open questions and blockers

**Blocked on the project owner:**

- **The custom domain hostname.**

**Decided by the owner, recorded so it is not relitigated:**

- The maintainer's own listing of downstream projects is out of scope — publish
  independently, tell him afterwards. Nothing about the maintainer's site goes in the repo or
  the interface. The required attribution is separate and unchanged.
- Deploy target is Netlify, not GitHub Pages.
- `is_reliable_only` is relaxed for the tool's basket only (findings §7).

## Known constraints

- **`hammer.duckdb` holds snapshot `20260911T200435Z`, not the snapshot the Phase 2 and
  Phase 3 numbers were computed on.** That build is preserved as
  `hammer-20260822T134045Z.duckdb` (renamed, because `scripts/load_snapshot.py` deletes the
  target database before loading). Reproduce any published Phase 2/3 figure against that file.
- **`is_reliable_only` is relaxed for the tool's basket only.** Phase 2's published figures
  were computed under the strict filter and are unchanged — do not recompute them. The
  relaxation rests on a guarantee asserted in `E1_tool_extract.sql`: no fuzzy-tier vendor's
  price can reach the extract. If that assertion fires, do not widen the allowed tiers to
  make it pass; re-examine the relaxation.
- **Deploy gate floors** are 4,000 products and 50% comparable, calibrated 2026-09-12 against
  a 6,090 / 65.30% population; the calibration is recorded beside them in
  `scripts/check_extract.py`.
- **Netlify's site settings show an empty publish directory.** `netlify.toml` supplies
  `_site` and takes precedence, and the push-triggered build demonstrably used it. If the toml
  is ever removed, the site will publish the repository root.
- The full data rebuild does not fit a CI runner (~10 GB working set). `scripts/refresh.py`
  runs locally and commits the extract; the push then deploys it through Netlify's gated build.

## Anything the next agent should distrust

- **The gates running on Netlify's builder are inferred, not read from a log.** The build API
  returned no log lines. The evidence is indirect but strong: the build command is
  `bash scripts/netlify_build.sh`, which runs `check_extract.py` under `set -euo pipefail`
  before it assembles anything, and the published deploy serves `/dashboard/` — a path that
  exists only because that script assembled `_site`. A build log read from the Netlify UI
  would make it direct.
- **The refusal path has never run on Netlify.** Both refusals (a non-production context and
  a failing extract) were demonstrated locally and from a fresh clone, never on the builder.
- **`probe.yml` has never executed.** It parses, and the script it calls has been run by hand.
- **The Section 2 and 3 numbers in `docs/phase-4-findings.md` describe the superseded
  2026-08-21 strict-filter extract** (2,921 products, 60.93%). §6–§8 carry the current figures.
- **`.handoff/invoke_codex.sh`'s interactive "yes" path has never been exercised** — every
  run ended in a non-interactive abort or a TTY error.
- Use `scripts/serve_gzip.py`, not `python -m http.server`, for anything performance-related:
  the plain server does not compress and overstated transfer cost by 12× once already.
