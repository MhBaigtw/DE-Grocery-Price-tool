#!/usr/bin/env python3
"""Download a Project Hammer dataset snapshot and record its provenance.

Locked decision #2 (CLAUDE.md): every downloaded copy is stored with its download
timestamp and a sha256 of the archive, and is never modified in place.

Writes archives to data/snapshots/<utc-stamp>/ alongside a manifest.json recording
url, download start/end timestamps (UTC), byte size, and sha256 of each archive.
Also captures hammer-lastupdated.txt at download time, because dataset freshness is
only meaningful relative to when we pulled.

No third-party dependencies. Re-running creates a NEW snapshot directory; it never
overwrites an existing one.
"""
import datetime
import hashlib
import json
import pathlib
import sys
import urllib.request

BASE = "https://jacobfilipp.com"
ARCHIVES = {
    "hammer-5-csv.zip": f"{BASE}/hammerdata/hammer-5-csv.zip",
    "hammer-3-compressed.zip": f"{BASE}/hammerdata/hammer-3-compressed.zip",
}
LASTUPDATED_URL = f"{BASE}/hammerdata/hammer-lastupdated.txt"
# Identify ourselves to the upstream host. A contact point is the courteous thing for any
# automated fetcher to carry -- it lets a maintainer say "stop" or "slow down" without
# guessing who we are. It should be the REPOSITORY, not a person: a personal address in a
# public repo is harvested by address scrapers within days, and the repo URL is a better
# contact anyway because it does not go stale when a person changes address.
#
# Set REPO_URL to the published repository once the remote exists. Until then the UA
# carries no contact at all, which is honest -- an unreachable or invented URL would be
# worse than none.
REPO_URL = ""  # e.g. "https://github.com/<owner>/<repo>"
UA = ("Mozilla/5.0 (Project Hammer downstream analysis"
      + (f"; +{REPO_URL}" if REPO_URL else "") + ")")
CHUNK = 1 << 20


def utcnow() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def fetch_text(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read().decode("utf-8", "replace")


def fetch_archive(url: str, dest: pathlib.Path) -> dict:
    """Stream to disk, hashing as we go. Returns a provenance record."""
    started = utcnow()
    digest = hashlib.sha256()
    size = 0
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=600) as r, open(dest, "wb") as fh:
        while True:
            chunk = r.read(CHUNK)
            if not chunk:
                break
            digest.update(chunk)
            fh.write(chunk)
            size += len(chunk)
            print(f"  {dest.name}: {size/1e6:8.1f} MB", end="\r", flush=True)
    print()
    dest.chmod(0o444)  # read-only: snapshots are immutable
    return {
        "url": url,
        "filename": dest.name,
        "download_started_utc": started,
        "download_finished_utc": utcnow(),
        "bytes": size,
        "sha256": digest.hexdigest(),
    }


def main() -> int:
    repo = pathlib.Path(__file__).resolve().parent.parent
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    snap = repo / "data" / "snapshots" / stamp
    if snap.exists():
        print(f"refusing to overwrite existing snapshot {snap}", file=sys.stderr)
        return 1
    snap.mkdir(parents=True)

    lastupdated = fetch_text(LASTUPDATED_URL).strip()
    print(f"upstream last-updated: {lastupdated!r}")

    manifest = {
        "snapshot_id": stamp,
        "captured_utc": utcnow(),
        "upstream_lastupdated_raw": lastupdated,
        "lastupdated_url": LASTUPDATED_URL,
        "archives": [],
    }
    for name, url in ARCHIVES.items():
        print(f"downloading {url}")
        manifest["archives"].append(fetch_archive(url, snap / name))

    (snap / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    print(f"\nsnapshot written to {snap}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
