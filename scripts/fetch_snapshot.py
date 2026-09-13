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
import argparse
import datetime
import hashlib
import http.client
import json
import re
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
REPO_URL = "https://github.com/MhBaigtw/DE-Grocery-Price-tool"
UA = ("Mozilla/5.0 (Project Hammer downstream analysis"
      + (f"; +{REPO_URL}" if REPO_URL else "") + ")")
CHUNK = 1 << 20

# WHAT A GENUINE ANSWER LOOKS LIKE. On 2026-09-13 the upstream host answered one GitHub runner
# with a bot-verification challenge page instead of the files, and this script saved that page
# under the archive's name and recorded its HTML as upstream's last-updated stamp. A later zip
# check refused it, by accident rather than design. Now both answers are validated before
# anything is written or recorded: a stamp must look like a stamp, and an archive must be
# served as a zip AND start with a zip header. Anything else is refused, never retried here, and
# never disguised around -- the client stays the honest UA above (docs/phase-4-findings.md §11).
STAMP = re.compile(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)? \(Eastern Time\)$")
ZIP_TYPES = ("application/zip", "application/x-zip-compressed")
ZIP_MAGIC = b"PK\x03\x04"


class UpstreamRefused(Exception):
    """Upstream answered, but not with what was asked for. Nothing was written or recorded."""


def describe(body: bytes, ctype: str) -> str:
    text = body[:8192].decode("utf-8", "replace")
    if "request is being verified" in text:
        kind = "a bot-verification challenge page"
    elif "<html" in text.lower():
        kind = "an HTML page"
    elif not body:
        kind = "an empty body"
    else:
        kind = "unexpected content"
    return f"{kind} (Content-Type {ctype or 'none'}; begins {' '.join(text.split())[:60]!r})"


def utcnow() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def fetch_text(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read().decode("utf-8", "replace")


def fetch_stamp(url: str | None = None) -> str:
    """Upstream's last-updated stamp, or UpstreamRefused. Never returns anything else."""
    url = url or LASTUPDATED_URL
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=120) as r:
        ctype = r.headers.get("Content-Type", "")
        body = r.read(65536)
    text = body.decode("utf-8", "replace").strip()
    if not STAMP.match(text):
        raise UpstreamRefused(f"{url} did not return a last-updated stamp: got {describe(body, ctype)}")
    return text


def fetch_archive(url: str, dest: pathlib.Path) -> dict:
    """Stream to disk, hashing as we go. Returns a provenance record.

    The content type and the first bytes are checked BEFORE the destination file is created,
    so a page that is not an archive never exists under an archive's name and never reaches a
    manifest. A body shorter than its announced length is refused and deleted."""
    started = utcnow()
    digest = hashlib.sha256()
    size = 0
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=600) as r:
        ctype = (r.headers.get("Content-Type") or "").split(";")[0].strip().lower()
        announced = r.headers.get("Content-Length")
        first = r.read(CHUNK)
        if ctype not in ZIP_TYPES or not first.startswith(ZIP_MAGIC):
            raise UpstreamRefused(f"{url} did not return a zip archive: got {describe(first, ctype)}")
        try:
            with open(dest, "wb") as fh:
                chunk = first
                while chunk:
                    digest.update(chunk)
                    fh.write(chunk)
                    size += len(chunk)
                    print(f"  {dest.name}: {size/1e6:8.1f} MB", end="\r", flush=True)
                    chunk = r.read(CHUNK)
        except http.client.IncompleteRead as e:
            dest.unlink(missing_ok=True)
            raise UpstreamRefused(f"{url}: the transfer ended early ({e})") from e
    print()
    if announced is not None and int(announced) != size:
        dest.unlink(missing_ok=True)
        raise UpstreamRefused(f"{url}: received {size:,} bytes of an announced {int(announced):,}")
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
    # Argument parsing exists so that `--help` PRINTS HELP rather than starting a 1.4 GB
    # download. Before this, the script ignored argv entirely: any argument -- including
    # `--help` -- fell straight through to creating a snapshot directory and opening a
    # network connection. That was found by following the README's reproduce steps
    # literally instead of reading them, which is the point of doing it that way.
    ap = argparse.ArgumentParser(
        description="Download a Project Hammer snapshot into data/snapshots/<utc-stamp>/ "
                    "with provenance (sha256, download timestamps, upstream "
                    "hammer-lastupdated.txt). Downloads ~1.4 GB. Never overwrites an "
                    "existing snapshot.")
    ap.add_argument("--dry-run", action="store_true",
                    help="report what would be downloaded and exit without writing "
                         "anything or fetching an archive")
    args = ap.parse_args()

    repo = pathlib.Path(__file__).resolve().parent.parent
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    if args.dry_run:
        print(f"would create : {repo / 'data' / 'snapshots' / stamp}")
        for name, url in ARCHIVES.items():
            print(f"would fetch  : {url}")
        print(f"would record : {LASTUPDATED_URL}")
        print()
        print("dry run - nothing downloaded, nothing written.")
        return 0

    snap = repo / "data" / "snapshots" / stamp
    if snap.exists():
        print(f"refusing to overwrite existing snapshot {snap}", file=sys.stderr)
        return 1
    snap.mkdir(parents=True)

    lastupdated = fetch_stamp()
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
