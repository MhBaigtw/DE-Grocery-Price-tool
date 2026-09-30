#!/usr/bin/env python3
"""Asserts the refresh workflow cannot leave a stale site unannounced.

WHY. On 2026-09-30 the probe's "the live site is behind" alert was removed, because the publish
job that follows it usually fixes the thing it was shouting about. Removing a false positive is
how you create a blind spot: the remaining alert was conditioned on a check that never runs when
the publish step itself fails, so a failed upload would have said nothing at all. This asserts
the properties that must hold however the alerting is arranged:

  1. something reports whether the live site matches main, daily;
  2. a site found behind triggers a publish;
  3. the publish job verifies the live site afterwards, compression included;
  4. an alert fires when the publish FAILS, not only when it succeeds and the site is stale;
  5. that path also fails the run, so it is red as well as noisy.

It reads the workflow rather than the intent, so an edit that quietly drops one fails here.

Run: python scripts/test_workflow_alerts.py
"""
from __future__ import annotations
import pathlib, sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
WF = ROOT / ".github" / "workflows" / "refresh.yml"


def main() -> int:
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except Exception:                                      # noqa: BLE001
            pass
    wf = yaml.safe_load(WF.read_text(encoding="utf-8"))
    jobs = wf["jobs"]
    probe, publish = jobs["probe"], jobs["publish"]
    probe_steps = probe["steps"]
    publish_steps = publish["steps"]

    def runs(steps, needle):
        return [s for s in steps if needle in str(s.get("run", "")) or needle in str(s.get("with", {}).get("script", ""))]

    checks = []

    def check(name, ok, detail=""):
        checks.append(ok)
        print(f"  {'PASS' if ok else 'FAIL'}  {name}" + ("" if ok else f"\n        {detail}"))

    # 1. the daily report
    probe_check = runs(probe_steps, "check_published.py")
    check("the probe checks daily whether the live site matches main",
          bool(probe_check), "no step in the probe job runs check_published.py")
    check("the probe publishes that result as a job output",
          "published" in str(probe.get("outputs", {})),
          f"probe outputs are {probe.get('outputs')}")

    # 2. a site found behind triggers a publish
    check("a site found behind triggers the publish job",
          "published_ok" in str(publish.get("if", "")),
          f"publish job condition does not consider it: {publish.get('if')}")

    # 3. the deployed site is verified, compression included
    check("the publish job verifies the live site (verify_deploy.py)",
          bool(runs(publish_steps, "verify_deploy.py")),
          "nothing in the publish job runs verify_deploy.py, so compression is unchecked")

    # 4. an alert that survives a failed upload
    alerts = [s for s in publish_steps if "github-script" in str(s.get("uses", ""))
              and "issues.create" in str(s.get("with", {}).get("script", ""))]
    check("the publish job opens or updates an issue when things go wrong", bool(alerts),
          "no alert step in the publish job")
    covers_failure = any("failure()" in str(a.get("if", "")) for a in alerts)
    check("that alert fires when the publish step itself fails, not only when the check reports",
          covers_failure,
          "every alert is conditioned on a step outcome; if the upload fails that step never "
          "runs and nothing alerts -- the blind spot this test exists for")

    # 5. and the run goes red
    reds = [s for s in publish_steps if str(s.get("run", "")).strip().endswith("exit 1")]
    check("a site still behind after publishing fails the run", bool(reds),
          "nothing fails the publish job, so it would be green with a stale site")

    print(f"\n{sum(checks)} of {len(checks)} properties hold.")
    if not all(checks):
        print("FAIL - the workflow could leave the live site stale without saying so.")
        return 1
    print("OK - a stale site is always reported, whichever way the publish fails.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
