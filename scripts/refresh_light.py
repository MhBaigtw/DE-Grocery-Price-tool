#!/usr/bin/env python3
"""The light refresh: rebuild the tool's extract from upstream's newest publication without
building the full analysis database. Runs on a GitHub-hosted runner, and is triggered by
upstream publishing, not by a clock.

WHY IT EXISTS. The full refresh (scripts/refresh.py) needs ~1.45 GB of archives, a 4.4 GB SQLite
file and a multi-GB DuckDB. It does not fit a hosted runner, so it cannot run unattended for
free. The tool does not need most of that: it reads two chains. Loading only Metro and Walmart
keeps about a fifth of the price rows. It loads their FULL history, because E1's basket rule
counts co-observed days back to 2024-06-11, so "recent dates only" would change the extract.
Measured on snapshot 20260911T200435Z: peak disk ~5 GiB, peak memory 2.7 GiB, and output
byte-identical to the full path (docs/phase-4-findings.md §10).

TRIGGER. Publication, not a clock. `--probe-only` reads hammer-lastupdated.txt (a few hundred
bytes) and compares it with the newest record in data/provenance/. Only a change starts a
refresh. Pulling daily regardless would buy about one percentage point of staleness over a
correctly timed refresh, and cost the maintainer's server seven times the bandwidth (§1.4).

CHEAPER MUST NOT MEAN LESS GUARDED. Every gate that guards the extract's correctness runs here.
Any refusal stops the run before anything is committed:
  1. the filter matches what the extract reads (asserted against E1 and check_extract.py)
  2. the schema contract. The SQLite archive is used, not the CSV, because a CSV carries no
     column types and the announced product_id type change would pass unseen.
  3. the model row-count contracts (build_models.py)
  4. the layering, determinism and model-parity checks
  5. E1 built twice by verify_twice.py; E1 itself asserts in SQL that no fuzzy-tier price can
     reach the extract
  6. the extract gate (floors, structure, vintage)
  7. the render gate and the file manifest, whenever the extract is written into the repository
It does NOT run the dbt suite or verify_reproducible, which need the full database. Those run
with every full rebuild, which also runs check_light_parity.py: the proof that this filter
drops nothing the extract needs.

TOLERANCE, NOT PERSISTENCE (added 2026-09-13, §11). Every request to upstream is validated: a
stamp must be a stamp, and an archive must be served as a zip and start with a zip header,
checked before it is used or recorded. A refused answer, such as the bot-verification challenge
page one runner received on the first run, is retried at most three times, at 0, +15 and +45
minutes, and then the run fails and alerts. Never more than that: repeated requests to a
volunteer's server are their own problem. The client stays the honest user agent; nothing
disguises it or attempts the challenge.

PROVENANCE, NOT ARCHIVES (CLAUDE.md locked decision 2, amended 2026-09-12). A fetched run records
the download timestamps, sha256, byte size and upstream's last-updated stamp in
data/provenance/<snapshot_id>.json, commits it with the extract, and deletes the archive.

  python scripts/refresh_light.py --probe-only    # has upstream published since the newest record?
  python scripts/refresh_light.py                 # probe; on a change: fetch, build, gate, write tool/data
  python scripts/refresh_light.py --snapshot data/snapshots/<id> --out <dir>
                                                  # build from an archive already on disk (no fetch)
"""
from __future__ import annotations
import argparse, datetime as dt, json, os, pathlib, re, shutil, subprocess, sys, tempfile
import threading, time

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import fetch_snapshot  # noqa: E402  -- one fetcher: UA, archive URLs, streaming sha256

import http.client  # noqa: E402

PY = sys.executable
# Attempt start times, in seconds after the first. Capped in code, not just by default.
DEFAULT_RETRY_AT = "0,900,2700"
MAX_ATTEMPTS, MAX_SPAN_S = 3, 3600
# The chains the light load keeps. Asserted, not trusted: see assert_filter_matches_extract().
LIGHT_VENDORS = ("Metro", "Walmart")
E1 = ROOT / "analysis" / "phase4" / "E1_tool_extract.sql"
PROVENANCE = ROOT / "data" / "provenance"
SQLITE_ARCHIVE = "hammer-3-compressed.zip"


class Stop(Exception):
    """A gate refused. Nothing is committed and the previous extract stays live."""


def say(step: str, msg: str = "") -> None:
    print(f"[{dt.datetime.now(dt.timezone.utc):%H:%M:%S}] {step:<16} {msg}", flush=True)


def run(step: str, cmd: list, cwd: pathlib.Path = ROOT) -> str:
    cmd = [str(c) for c in cmd]
    say(step, " ".join(cmd[1:]) if cmd[0] == PY else " ".join(cmd))
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8",
                       errors="replace")
    # Every step's output is printed, not only a failing one: a gate that passes silently is a
    # gate whose result nobody can read.
    for line in (p.stdout + p.stderr).strip().splitlines()[-14:]:
        print("                   | " + line, flush=True)
    if p.returncode != 0:
        raise Stop(f"{step} failed (exit {p.returncode})")
    return p.stdout


class Meter:
    """Optional per-stage wall-clock, peak RSS (this process and its children) and peak disk
    under the work directory. Needs psutil; off unless --measure."""

    def __init__(self, on: bool, workdir: pathlib.Path):
        self.on, self.workdir, self.rows = on, workdir, []
        self.peak_rss = self.peak_disk = 0
        if on:
            import psutil
            self.ps = psutil
            threading.Thread(target=self._poll, daemon=True).start()

    def _rss(self) -> int:
        me, total = self.ps.Process(), 0
        for p in [me] + me.children(recursive=True):
            try:
                total += p.memory_info().rss
            except self.ps.Error:
                pass
        return total

    def _disk(self) -> int:
        total = 0
        for r, _, files in os.walk(self.workdir):
            for f in files:
                try:
                    total += os.path.getsize(os.path.join(r, f))
                except OSError:
                    pass
        return total

    def _poll(self) -> None:
        while True:
            self.peak_rss = max(self.peak_rss, self._rss())
            self.peak_disk = max(self.peak_disk, self._disk())
            time.sleep(0.5)

    def stage(self, name: str, fn):
        if self.on:
            self.peak_rss, self.peak_disk = self._rss(), self._disk()
        t = time.time()
        out = fn()
        if self.on:
            self.rows.append((name, time.time() - t, self.peak_rss, self.peak_disk))
        return out

    def report(self) -> None:
        if not self.rows:
            return
        print("\nstage                seconds   peak RSS GiB   peak work-dir disk GiB")
        for n, t, r, d in self.rows:
            print(f"{n:<18} {t:9.1f} {r / 2**30:14.2f} {d / 2**30:24.2f}")
        print(f"{'total / peak':<18} {sum(x[1] for x in self.rows):9.1f} "
              f"{max(x[2] for x in self.rows) / 2**30:14.2f} "
              f"{max(x[3] for x in self.rows) / 2**30:24.2f}")


def assert_filter_matches_extract() -> None:
    """The filter is only safe if it loads every chain the extract reads. If E1 or the extract
    gate ever gains a chain and this list does not, the light extract would silently lack its
    rows and still pass every floor. Refuse instead."""
    lists = re.findall(r"vendor\s+(?:NOT\s+)?IN\s*\(([^)]*)\)", E1.read_text(encoding="utf-8"),
                       flags=re.I)
    if not lists:
        raise Stop("found no vendor list in E1 to check the light filter against")
    for group in lists:
        names = set(re.findall(r"'([^']+)'", group))
        if names != set(LIGHT_VENDORS):
            raise Stop(f"E1 reads vendors {sorted(names)} but the light load keeps "
                       f"{sorted(LIGHT_VENDORS)}: the light extract would lack rows. "
                       "Change LIGHT_VENDORS and E1 together.")
    import check_extract
    if set(check_extract.ALLOWED_CHAINS) != set(LIGHT_VENDORS):
        raise Stop(f"check_extract.py allows {sorted(check_extract.ALLOWED_CHAINS)} but the "
                   f"light load keeps {sorted(LIGHT_VENDORS)}")
    say("filter", f"keeps {', '.join(LIGHT_VENDORS)}; matches all {len(lists)} vendor lists "
                  "in E1 and the extract gate")


def retry_schedule(spec: str) -> tuple[int, ...]:
    try:
        at = tuple(int(x) for x in spec.split(","))
    except ValueError:
        raise Stop(f"retry schedule {spec!r} is not a list of seconds")
    if (not at or at[0] != 0 or list(at) != sorted(at) or len(at) > MAX_ATTEMPTS
            or at[-1] > MAX_SPAN_S):
        raise Stop(f"retry schedule {spec!r} refused: at most {MAX_ATTEMPTS} attempts, the first "
                   f"at 0, all within {MAX_SPAN_S // 60} minutes. Repeated requests to a "
                   "volunteer's server are their own problem.")
    return at


def with_retries(what: str, fn, at: tuple[int, ...], sleep=time.sleep):
    """Tolerance for a transient refusal, not persistence: at most len(at) attempts, at the
    given offsets, then Stop. A refusal is a validated non-answer (UpstreamRefused) or a
    network error; anything else is a bug and is not retried."""
    start = time.monotonic()
    last = None
    for i, t in enumerate(at, 1):
        wait = t - (time.monotonic() - start)
        if wait > 0:
            say("retry", f"{what}: attempt {i} of {len(at)} in {wait / 60:.1f} min")
            sleep(wait)
        try:
            return fn()
        except (fetch_snapshot.UpstreamRefused, OSError, http.client.HTTPException) as e:
            last = e
            say("refused", f"{what}: attempt {i} of {len(at)}: {e}")
    raise Stop(f"{what}: upstream refused all {len(at)} attempts; last: {last}")


def latest_record() -> dict | None:
    recs = sorted(PROVENANCE.glob("*.json"))
    return json.loads(recs[-1].read_text(encoding="utf-8")) if recs else None


def probe(at: tuple[int, ...]) -> tuple[str, bool]:
    raw = with_retries("probe", fetch_snapshot.fetch_stamp, at)
    say("probe", f"upstream last-updated {raw!r}")
    rec = latest_record()
    have = rec.get("upstream_lastupdated_raw") if rec else None
    say("recorded", f"{have!r} (record {rec['snapshot_id']}, {rec['path']} path)" if rec
        else "no provenance record")
    return raw, raw != have


def emit(key: str, value: str) -> None:
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a", encoding="utf-8") as fh:
            fh.write(f"{key}={value}\n")


def fetch(workdir: pathlib.Path, at: tuple[int, ...]) -> tuple[pathlib.Path, dict]:
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    snap = workdir / "snapshot" / stamp
    snap.mkdir(parents=True)
    lastupdated = with_retries("last-updated stamp", fetch_snapshot.fetch_stamp, at)
    # Validated before the manifest exists: a refused archive leaves no manifest to record.
    archive = with_retries("archive", lambda: fetch_snapshot.fetch_archive(
        fetch_snapshot.ARCHIVES[SQLITE_ARCHIVE], snap / SQLITE_ARCHIVE), at)
    manifest = {
        "snapshot_id": stamp,
        "captured_utc": fetch_snapshot.utcnow(),
        "upstream_lastupdated_raw": lastupdated,
        "lastupdated_url": fetch_snapshot.LASTUPDATED_URL,
        "archives": [archive],
    }
    (snap / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return snap, manifest


def build(snap: pathlib.Path, out: pathlib.Path, workdir: pathlib.Path, vintage: str,
          into_repo: bool, meter: Meter) -> pathlib.Path:
    db = workdir / "light.duckdb"
    (out / "tool" / "data").mkdir(parents=True, exist_ok=True)
    meter.stage("filtered load", lambda: run("load", [
        PY, "scripts/load_snapshot.py", snap, "--db", db, "--workdir", workdir,
        "--vendors", ",".join(LIGHT_VENDORS), "--drop-sqlite"]))
    meter.stage("schema contract", lambda: run("schema gate", [
        PY, "scripts/check_schema.py", "--db", db]))
    meter.stage("build models", lambda: run("build models", [
        PY, "scripts/build_models.py", "--db", db, "--materialize", "table"]))
    meter.stage("code checks", lambda: [
        run("layering", [PY, "scripts/check_layering.py"]),
        run("determinism", [PY, "scripts/check_determinism.py"]),
        run("model parity", [PY, "scripts/check_model_parity.py"])])
    meter.stage("extract x2", lambda: run("extract x2", [
        PY, "scripts/verify_twice.py", "analysis/phase4/E1_tool_extract.sql", "--db", db,
        "--cwd", out, "--memory-limit", "5GB", "--max-rows", "40",
        "--temp-dir", workdir / "spill", "--save", workdir / "E1_light.log"]))
    meter.stage("extract gate", lambda: run("extract gate", [
        PY, "scripts/check_extract.py", "--dir", out / "tool" / "data", "--vintage", vintage]))
    if into_repo:
        meter.stage("render gate", lambda: run("render gate", ["node", "scripts/test_tool_render.js"]))
    return db


def write_record(manifest: dict, out: pathlib.Path, path: str, archive_retained: bool,
                 db: pathlib.Path | None = None) -> pathlib.Path:
    """The provenance of what shipped. Also the trigger's baseline: the next probe compares
    upstream's last-updated stamp with the newest of these records."""
    meta = json.loads((out / "tool" / "data" / "meta.json").read_text(encoding="utf-8"))
    load_filter = None
    if db is not None:
        import duckdb
        con = duckdb.connect(str(db), read_only=True)
        kv = dict(con.execute("SELECT k, v FROM _snapshot_provenance").fetchall())
        con.close()
        load_filter = {k: (v if k == "load_filter" else int(v)) for k, v in kv.items()
                       if k == "load_filter" or k.endswith("_rows_source") or k.endswith("_rows_loaded")}
    run_url = None
    if os.environ.get("GITHUB_RUN_ID"):
        run_url = (f"{os.environ.get('GITHUB_SERVER_URL')}/{os.environ.get('GITHUB_REPOSITORY')}"
                   f"/actions/runs/{os.environ['GITHUB_RUN_ID']}")
    rec = {
        "snapshot_id": manifest["snapshot_id"],
        "path": path,
        "captured_utc": manifest["captured_utc"],
        "upstream_lastupdated_raw": manifest["upstream_lastupdated_raw"],
        "lastupdated_url": manifest["lastupdated_url"],
        "archives": manifest["archives"],
        "archive_retained": archive_retained,
        "load_filter": load_filter,
        "extract": {k: meta[k] for k in ("extract_date", "products_shipped", "built_utc")},
        "run": run_url,
    }
    PROVENANCE.mkdir(parents=True, exist_ok=True)
    dest = PROVENANCE / f"{manifest['snapshot_id']}.json"
    dest.write_text(json.dumps(rec, indent=2) + "\n", encoding="utf-8")
    return dest


def record_full(snap_dir: pathlib.Path) -> pathlib.Path:
    """Called by refresh.py after a full rebuild: the archive is retained under data/snapshots/."""
    manifest = json.loads((snap_dir / "manifest.json").read_text(encoding="utf-8"))
    return write_record(manifest, ROOT, "full", archive_retained=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--probe-only", action="store_true",
                    help="report whether upstream has published since the newest record, then stop")
    ap.add_argument("--force", action="store_true",
                    help="refresh even if upstream's last-updated stamp matches the newest record")
    ap.add_argument("--snapshot", default=None,
                    help="build from a snapshot directory already on disk: no probe, no fetch, "
                         "no provenance record, and the archive is never deleted")
    ap.add_argument("--out", default=str(ROOT),
                    help="directory to write tool/data/ under (default: the repository)")
    ap.add_argument("--workdir", default=None,
                    help="scratch directory (default: a new temporary directory, removed after)")
    ap.add_argument("--vintage", choices=["fail", "warn"], default="fail",
                    help="passed to check_extract.py; 'warn' only for building an old snapshot "
                         "to compare or measure, never for a deploy")
    ap.add_argument("--measure", action="store_true",
                    help="report wall-clock, peak memory and peak disk per stage (needs psutil)")
    ap.add_argument("--retry-at", default=DEFAULT_RETRY_AT,
                    help="attempt start offsets in seconds for each upstream request (default "
                         "0,900,2700). Capped at 3 attempts within an hour; a longer schedule "
                         "is refused.")
    args = ap.parse_args()
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except Exception:                                      # noqa: BLE001
            pass

    workdir = None
    meter = None
    try:
        assert_filter_matches_extract()
        at = retry_schedule(args.retry_at)
        if args.probe_only:
            _, changed = probe(at)
            say("decision", "REFRESH -- upstream has published since the newest record"
                if changed else "hold -- nothing new upstream")
            emit("changed", "true" if changed else "false")
            return 0

        out = pathlib.Path(args.out).resolve()
        into_repo = out == ROOT.resolve()
        if into_repo and args.vintage != "fail":
            raise Stop("--vintage warn is for building into a scratch directory, never into the "
                       "repository's tool/data/")
        workdir = (pathlib.Path(args.workdir).resolve() if args.workdir
                   else pathlib.Path(tempfile.mkdtemp(prefix="light_")))
        workdir.mkdir(parents=True, exist_ok=True)
        meter = Meter(args.measure, workdir)

        if args.snapshot:
            snap = pathlib.Path(args.snapshot).resolve()
            manifest = json.loads((snap / "manifest.json").read_text(encoding="utf-8"))
            fetched = False
        else:
            _, changed = probe(at)
            if not changed and not args.force:
                say("decision", "hold -- nothing new upstream")
                return 0
            say("decision", "REFRESH" + (" (forced)" if not changed else ""))
            snap, manifest = meter.stage("download", lambda: fetch(workdir, at))
            fetched = True

        say("snapshot", f"{manifest['snapshot_id']}, upstream {manifest['upstream_lastupdated_raw']!r}")
        db = build(snap, out, workdir, args.vintage, into_repo, meter)

        if fetched:
            archive = snap / SQLITE_ARCHIVE
            archive.chmod(0o644)
            archive.unlink()
            say("archive", "deleted: provenance is recorded, the archive is not retained "
                           "(locked decision 2, amended 2026-09-12)")
            if into_repo:
                dest = write_record(manifest, out, "light", archive_retained=False, db=db)
                say("provenance", str(dest.relative_to(ROOT)))
                run("manifest", [PY, "scripts/check_manifest.py"])

        say("done", f"extract written to {out / 'tool' / 'data'}")
        return 0
    except Stop as e:
        say("REFUSED", str(e))
        print("\nThe light refresh did not complete. Nothing was committed and the previous "
              "extract stays live.")
        return 1
    finally:
        if meter is not None:
            meter.report()
        if workdir is not None and not args.workdir:
            shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
