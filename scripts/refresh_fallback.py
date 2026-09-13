#!/usr/bin/env python3
"""FALLBACK refresh from this Windows PC, run by Task Scheduler. NOT the primary path.

THE PRIMARY PATH is .github/workflows/refresh.yml on a GitHub-hosted runner. This exists
because on 2026-09-13 the first automated run was refused by a bot-verification challenge from
the upstream host (docs/phase-4-findings.md §11). A home connection has not been challenged, so
a second route keeps the site fresh on days the runner is refused.

IT RUNS ONLY WHILE THIS PC IS ON, AND ONLY WHILE ITS USER IS LOGGED ON. A PC that is off,
asleep or logged out refreshes nothing. Task Scheduler starts a missed run when the machine
next becomes available, not before. Nothing here makes that otherwise.

WHAT IT DOES, IN ORDER. Each step refuses rather than guesses:
  1. Refuses unless the repository is on main, with a clean working tree and no unpushed
     commits. It will not commit around work in progress or push someone else's commits.
  2. Holds if a GitHub refresh run is queued or in progress, so the two never race for the
     same publication.
  3. git pull --ff-only, so the trigger compares against the newest provenance record,
     including one the workflow just committed.
  4. python scripts/refresh_light.py: the same probe, validation, retries and gates as the
     workflow.
  5. If tool/data/ or data/provenance/ changed, it fetches again. If origin/main already
     carries a record of the same upstream publication, it discards this result. Otherwise it
     commits and pushes, and Netlify builds that push through its gates.
  6. On any failure it logs, then opens or comments on the same GitHub issue the workflow uses.
Log: logs/refresh_fallback-<utc>.log (gitignored).

  python scripts/refresh_fallback.py            # what the scheduled task runs
  powershell -File scripts/register_fallback_task.ps1 -Python <path to python.exe>
"""
from __future__ import annotations
import datetime as dt, json, pathlib, shutil, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PY = sys.executable
REPO = "MhBaigtw/DE-Grocery-Price-tool"
ISSUE_TITLE = "Automated refresh refused or failed"
LOG = ROOT / "logs" / f"refresh_fallback-{dt.datetime.now(dt.timezone.utc):%Y%m%dT%H%M%SZ}.log"


def log(msg: str) -> None:
    line = f"[{dt.datetime.now(dt.timezone.utc):%Y-%m-%d %H:%M:%S}Z] {msg}"
    print(line, flush=True)
    LOG.parent.mkdir(exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def sh(*cmd: str, check: bool = True) -> str:
    p = subprocess.run(list(cmd), cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
                       errors="replace")
    if check and p.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)} exited {p.returncode}: {(p.stdout + p.stderr).strip()[-400:]}")
    return p.stdout


class Hold(Exception):
    """Not a failure: nothing to do, or not safe to do it now."""


def preflight() -> None:
    branch = sh("git", "rev-parse", "--abbrev-ref", "HEAD").strip()
    if branch != "main":
        raise RuntimeError(f"on branch {branch!r}, not main; the fallback only refreshes main")
    if sh("git", "status", "--porcelain").strip():
        raise RuntimeError("the working tree is not clean; refusing to commit around work in progress")
    sh("git", "fetch", "--quiet", "origin")
    if sh("git", "rev-list", "--count", "origin/main..HEAD").strip() != "0":
        raise RuntimeError("main has unpushed commits; refusing to push them from a scheduled task")
    if shutil.which("gh"):
        active = sh("gh", "run", "list", "--repo", REPO, "--workflow", "refresh.yml", "--limit", "5",
                    "--json", "status", "-q", '[.[] | select(.status != "completed")] | length',
                    check=False).strip()
        if active not in ("", "0"):
            raise Hold("a GitHub refresh run is queued or in progress; the primary path has it")
    sh("git", "pull", "--ff-only", "--quiet", "origin", "main")


def publication_already_on_origin() -> bool:
    ours = sorted((ROOT / "data" / "provenance").glob("*.json"))[-1]
    stamp = json.loads(ours.read_text(encoding="utf-8"))["upstream_lastupdated_raw"]
    sh("git", "fetch", "--quiet", "origin")
    for name in sh("git", "ls-tree", "--name-only", "origin/main", "data/provenance/").split():
        rec = json.loads(sh("git", "show", f"origin/main:{name}"))
        if rec.get("upstream_lastupdated_raw") == stamp:
            return True
    return False


def alert(msg: str) -> None:
    if not shutil.which("gh"):
        log("gh is not available; the failure is only in this log")
        return
    body = (f"**The fallback refresh on the owner's PC did not complete.** Nothing was committed; "
            f"the site keeps serving the previous extract.\n\n```\n{msg[-1500:]}\n```\n\n"
            f"Log on that PC: `{LOG.relative_to(ROOT)}`")
    num = sh("gh", "issue", "list", "--repo", REPO, "--state", "open", "--search",
             f'"{ISSUE_TITLE}" in:title', "--json", "number", "-q", ".[0].number", check=False).strip()
    if num:
        sh("gh", "issue", "comment", num, "--repo", REPO, "--body", body, check=False)
    else:
        sh("gh", "issue", "create", "--repo", REPO, "--title", ISSUE_TITLE, "--body", body, check=False)


def main() -> int:
    log("fallback refresh starting (runs only while this PC is on and its user is logged on)")
    try:
        preflight()
        p = subprocess.run([PY, "scripts/refresh_light.py", "--measure"], cwd=ROOT,
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
        with open(LOG, "a", encoding="utf-8") as fh:
            fh.write(p.stdout + p.stderr)
        if p.returncode != 0:
            raise RuntimeError("refresh_light.py refused or failed:\n" + (p.stdout + p.stderr)[-1500:])
        if not sh("git", "status", "--porcelain", "--", "tool/data", "data/provenance").strip():
            raise Hold("nothing new upstream")
        if publication_already_on_origin():
            sh("git", "checkout", "--", "tool/data")
            sh("git", "clean", "-fq", "--", "data/provenance")
            raise Hold("origin/main already carries this publication (the workflow got there first); discarded")
        rec = json.loads(sorted((ROOT / "data" / "provenance").glob("*.json"))[-1].read_text(encoding="utf-8"))
        rec["run"] = "fallback on the owner's PC (scripts/refresh_fallback.py)"
        newest = sorted((ROOT / "data" / "provenance").glob("*.json"))[-1]
        newest.write_text(json.dumps(rec, indent=2) + "\n", encoding="utf-8")
        sh("git", "add", "tool/data", "data/provenance")
        sh("git", "commit", "-q", "-m",
           f"Refresh (fallback, owner's PC): snapshot {rec['snapshot_id']} - upstream "
           f"{rec['upstream_lastupdated_raw']} - extract {rec['extract']['extract_date']}")
        sh("git", "pull", "--rebase", "--quiet", "origin", "main")
        sh("git", "push", "--quiet", "origin", "HEAD:main")
        log(f"committed and pushed snapshot {rec['snapshot_id']}, extract {rec['extract']['extract_date']}")
        return 0
    except Hold as h:
        log(f"hold: {h}")
        return 0
    except Exception as e:                                     # noqa: BLE001
        log(f"FAILED: {e}")
        alert(str(e))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
