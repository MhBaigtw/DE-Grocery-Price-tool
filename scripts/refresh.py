#!/usr/bin/env python3
"""The FULL refresh: fetch, gate on schema, rebuild, check, regenerate the extract, gate
again. It does not deploy — it produces an extract that is safe to deploy, and says so.

SINCE 2026-09-12 THIS IS THE MANUAL, ANALYSIS PATH. The site is kept current by the automated
light refresh (scripts/refresh_light.py, .github/workflows/refresh.yml), which runs whenever
upstream publishes. This script remains the only path that builds the full database, retains
the archives (CLAUDE.md locked decision 2, as amended), runs the dbt suite and
verify_reproducible, and proves the light path's filter with check_light_parity.py. The
cadence notes below describe the weekly schedule it was written for.

CADENCE. Weekly, consuming Thursday's scrape, run Friday 05:00 UTC, with a daily cheap probe
of hammer-lastupdated.txt so a late file is picked up without pulling 1.45 GB a day. That
schedule is derived, not chosen: see docs/phase-4-findings.md §1.4. A daily full refresh
beats it by about one percentage point of staleness and costs seven times the bandwidth off
a volunteer's server.

WHERE THIS RUNS. Locally, or on a self-hosted runner — not on a hosted CI runner. The
working set is roughly 1.45 GB of archives plus an extracted SQLite plus a 3.2 GB DuckDB,
which does not fit the ~14 GB a GitHub-hosted runner offers. CI's job is the light half:
validate the committed extract and deploy it. See §4 of the findings.

EVERY STEP IS A GATE (brief §4.2, §4.3). Schema mismatch, a failed check, a determinism
violation or a thin extract all stop the run. Nothing half-built is left where a deploy
could find it: the extract is rebuilt into a scratch directory and only moved into place
once it has passed check_extract.py.

  python scripts/refresh.py --dry-run     # say what would happen, touch nothing
  python scripts/refresh.py --probe-only  # just ask upstream what it has published
  python scripts/refresh.py               # the real thing
"""
from __future__ import annotations
import argparse, datetime as dt, json, pathlib, shutil, subprocess, sys, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
SNAPDIR = ROOT / "data" / "snapshots"
EXTRACT = ROOT / "tool" / "data"
LASTUPDATED = "https://jacobfilipp.com/hammerdata/hammer-lastupdated.txt"
UA = ("Mozilla/5.0 (Project Hammer downstream analysis; "
      "+https://github.com/MhBaigtw/DE-Grocery-Price-tool)")

PY = sys.executable


class Stop(Exception):
    """A gate refused. The previous deploy stays live."""


def say(step: str, msg: str = "") -> None:
    print(f"[{dt.datetime.now(dt.timezone.utc):%H:%M:%S}] {step:<18} {msg}", flush=True)


def run(step: str, cmd: list[str], dry: bool, cwd: pathlib.Path = ROOT) -> str:
    say(step, " ".join(cmd[1:]) if cmd[0] == PY else " ".join(cmd))
    if dry:
        return ""
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    tail = "\n".join((p.stdout + p.stderr).strip().splitlines()[-14:])
    # Print every step output, not only a failing one. A gate that passes silently is a
    # gate whose result nobody can see, and the schema check in particular is something a
    # reader of the log needs to read rather than infer from the absence of an error.
    for line in tail.splitlines():
        print("                   | " + line, flush=True)
    if p.returncode != 0:
        raise Stop(f"{step} failed (exit {p.returncode})")
    return tail


# --------------------------------------------------------------------------- probe
def probe() -> dt.date | None:
    """Ask upstream what it has published. A few hundred bytes, not 1.45 GB."""
    req = urllib.request.Request(LASTUPDATED, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        raw = r.read().decode("utf-8", "replace").strip()
    say("probe", raw)
    for tok in raw.replace("(", " ").split():
        try:
            return dt.date.fromisoformat(tok[:10])
        except ValueError:
            continue
    return None


def current_extract_date() -> dt.date | None:
    f = EXTRACT / "meta.json"
    if not f.exists():
        return None
    return dt.date.fromisoformat(
        str(json.loads(f.read_text(encoding="utf-8"))["extract_date"])[:10])


def newest_snapshot() -> str | None:
    if not SNAPDIR.exists():
        return None
    ids = sorted(d.name for d in SNAPDIR.iterdir()
                 if d.is_dir() and (d / "manifest.json").exists())
    return ids[-1] if ids else None


def should_refresh(upstream: dt.date | None, have: dt.date | None, args) -> tuple[bool, str]:
    """Weekly on Friday, and every day after that until the file actually arrives."""
    today = dt.date.today()
    if args.force:
        return True, "forced"
    if upstream is None:
        return False, "could not read the upstream publication date"
    if have is not None and upstream <= have:
        return False, f"upstream {upstream} is not newer than the extract we hold ({have})"
    behind = (today - have).days if have else 999
    if today.weekday() == 4:                      # Friday: the scheduled slot
        return True, f"scheduled slot, upstream has {upstream}"
    if behind > args.catch_up_days:
        return True, (f"extract is {behind} days old, past the {args.catch_up_days}-day "
                      f"catch-up threshold; upstream has {upstream}")
    return False, (f"not the scheduled slot and only {behind} days behind; "
                   f"upstream {upstream} will be taken on Friday")


# --------------------------------------------------------------- step verification
# Every command this script will run, with the flags it will pass. A dry run PRINTS these;
# it does not check them, which is how two wrong argument spellings survived the first pass
# --- check_model_parity.py takes no arguments and run_dbt_tests.py wants --target, not
# --db. Both would have failed at 05:00 on a Friday. This resolves each command and asks
# argparse whether it accepts the flags, without running any of the work.
def verify_steps(args) -> int:
    import shutil as _sh
    checks = [
        ("fetch",         [PY, "scripts/fetch_snapshot.py"],                 ["--dry-run"]),
        ("load",          [PY, "scripts/load_snapshot.py"],                  ["--db"]),
        ("schema gate",   [PY, "scripts/check_schema.py"],                   ["--db"]),
        ("build models",  [PY, "scripts/build_models.py"],                   ["--db", "--materialize"]),
        ("layering",      [PY, "scripts/check_layering.py"],                 []),
        ("determinism",   [PY, "scripts/check_determinism.py"],              []),
        ("model parity",  [PY, "scripts/check_model_parity.py"],             []),
        ("reproducible",  [PY, "scripts/verify_reproducible.py"],            ["--db"]),
        ("dbt tests",     [PY, "scripts/run_dbt_tests.py"],                  ["--target"]),
        ("extract x2",    [PY, "scripts/verify_twice.py"],                   ["--memory-limit", "--max-rows", "--save"]),
        ("extract gate",  [PY, "scripts/check_extract.py"],                  ["--dir"]),
        ("render gate",   ["node", "scripts/test_tool_render.js"],           []),
        ("manifest",      [PY, "scripts/check_manifest.py"],                 []),
        ("light parity",  [PY, "scripts/check_light_parity.py"],             ["--workdir"]),
    ]
    bad = 0
    for name, cmd, flags in checks:
        exe, script = cmd[0], cmd[-1]
        if exe != PY and _sh.which(exe) is None:
            print(f"  MISSING  {name:<14} {exe} is not on PATH")
            bad += 1
            continue
        if not (ROOT / script).exists():
            print(f"  MISSING  {name:<14} {script}")
            bad += 1
            continue
        if exe != PY or not flags:
            print(f"  ok       {name:<14} {script}")
            continue
        # Ask the script's own parser what it accepts. --help never does the work.
        h = subprocess.run(cmd + ["--help"], cwd=ROOT, capture_output=True, text=True)
        text = h.stdout + h.stderr
        missing = [f for f in flags if f not in text]
        if missing:
            print(f"  WRONG    {name:<14} {script} does not accept {', '.join(missing)}")
            bad += 1
        else:
            print(f"  ok       {name:<14} {script} accepts {', '.join(flags)}")
    print()
    if bad:
        print(f"FAIL - {bad} step(s) would not run as written.")
        return 1
    print("OK - every step resolves and accepts the flags this script passes it.")
    return 0


# --------------------------------------------------------------------------- pipeline
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true",
                    help="print every step without fetching, writing or rebuilding")
    ap.add_argument("--probe-only", action="store_true",
                    help="ask upstream what it has published, then stop")
    ap.add_argument("--force", action="store_true",
                    help="refresh even if it is not the scheduled slot")
    ap.add_argument("--skip-fetch", action="store_true",
                    help="rebuild from the newest snapshot already on disk")
    ap.add_argument("--db", default=str(ROOT / "hammer.duckdb"))
    ap.add_argument("--dbt-target", default="dev", choices=["dev", "snapshot2", "all"])
    ap.add_argument("--verify-steps", action="store_true",
                    help="check that every step's command exists and accepts the flags "
                         "this script passes it, then stop")
    ap.add_argument("--catch-up-days", type=int, default=8,
                    help="refresh off-schedule once the extract is older than this "
                         "(default 8 = one interval plus the publication lag)")
    args = ap.parse_args()

    if args.verify_steps:
        return verify_steps(args)

    started = dt.datetime.now(dt.timezone.utc)
    have = current_extract_date()
    say("start", f"extract on disk: {have}   dry-run: {args.dry_run}")

    try:
        upstream = probe()
        if args.probe_only:
            go, why = should_refresh(upstream, have, args)
            say("decision", ("REFRESH -- " if go else "hold -- ") + why)
            return 0

        if not args.skip_fetch:
            go, why = should_refresh(upstream, have, args)
            say("decision", ("REFRESH -- " if go else "hold -- ") + why)
            if not go:
                return 0
            # 4.4 -- the archive keeps accruing. fetch_snapshot never overwrites.
            run("fetch", [PY, "scripts/fetch_snapshot.py"] + (["--dry-run"] if args.dry_run else []),
                dry=False)

        snap = newest_snapshot()
        if not snap:
            raise Stop("no snapshot on disk to build from")
        say("snapshot", snap)

        # 4.2 -- THE SCHEMA CHECK IS A GATE. An upstream type change stops the run; the
        # site keeps serving the last good extract rather than deploying something
        # unverified. This is the announced raw.product_id change, among others.
        run("load", [PY, "scripts/load_snapshot.py", snap, "--db", args.db], args.dry_run)
        run("schema gate", [PY, "scripts/check_schema.py", "--db", args.db], args.dry_run)
        run("build models", [PY, "scripts/build_models.py", "--db", args.db,
                             "--materialize", "table"], args.dry_run)

        # 4.3 -- the standing checks run in the pipeline, not just on a laptop.
        run("layering", [PY, "scripts/check_layering.py"], args.dry_run)
        run("determinism", [PY, "scripts/check_determinism.py"], args.dry_run)
        # check_model_parity compares model TEXT across the two build paths and takes no
        # arguments; run_dbt_tests selects a profile target rather than a database path.
        # Both spellings were wrong on the first pass and a dry run cannot catch that,
        # because a dry run prints commands without validating them. --verify-steps does.
        run("model parity", [PY, "scripts/check_model_parity.py"], args.dry_run)
        run("reproducible", [PY, "scripts/verify_reproducible.py", "--db", args.db], args.dry_run)
        run("dbt tests", [PY, "scripts/run_dbt_tests.py", "--target", args.dbt_target],
            args.dry_run)

        # The extract is built twice and compared, like every other published number.
        run("extract x2", [PY, "scripts/verify_twice.py",
                           "analysis/phase4/E1_tool_extract.sql",
                           "--memory-limit", "5GB", "--max-rows", "40",
                           "--save", "logs/E1.log"], args.dry_run)

        # 4.3 -- the deploy gate. Structure and floors, so a legitimate weekly change in
        # every count does not trip it, but a thin or dishonest extract does.
        run("extract gate", [PY, "scripts/check_extract.py"], args.dry_run)
        run("render gate", ["node", "scripts/test_tool_render.js"], args.dry_run)
        run("manifest", [PY, "scripts/check_manifest.py"], args.dry_run)

        # The light refresh's filter is proven here, not assumed (decided 2026-09-12). Build the
        # light extract from this same snapshot and require it to be byte-identical to the one
        # this full rebuild just produced. A mismatch means the filter drops or changes rows the
        # extract needs, so every automated refresh since the last passing check is suspect.
        run("light parity", [PY, "scripts/check_light_parity.py", snap], args.dry_run)

        # Record what this rebuild consumed. The automated light refresh starts only when
        # upstream's last-updated stamp differs from the newest record, so without this it
        # would re-fetch a publication a full rebuild had already shipped.
        if not args.dry_run:
            import refresh_light
            say("provenance", str(refresh_light.record_full(SNAPDIR / snap).relative_to(ROOT)))

    except Stop as e:
        say("REFUSED", str(e))
        print("\nThe refresh did not complete. Nothing was deployed and the previous "
              "extract stays live.\nThis is the designed behaviour: a refresh that fails "
              "any check does not ship (brief 4.2, 4.3).")
        return 1
    except Exception as e:                                     # noqa: BLE001
        say("ERROR", f"{type(e).__name__}: {e}")
        return 1

    took = (dt.datetime.now(dt.timezone.utc) - started).total_seconds()
    if args.dry_run:
        say("done", f"dry run, {took:.0f}s")
        print("\nDRY RUN - nothing was fetched, rebuilt or written. "
              "The steps above are what a real run would do.")
        return 0
    new = current_extract_date()
    say("done", f"extract now {new} (was {have}) in {took:.0f}s")
    print("\nOK - extract rebuilt and passed every gate. Safe to commit and deploy.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
