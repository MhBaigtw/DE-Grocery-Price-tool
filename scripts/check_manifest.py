#!/usr/bin/env python3
"""Check docs/FILES.md against the files actually tracked by git.

Reports two kinds of drift:
  * tracked files that no entry in FILES.md covers   (undocumented)
  * FILES.md entries that point at nothing on disk   (stale)

Entries are the `### path` headings in docs/FILES.md. A heading ending in `/` is a
directory entry and covers every tracked file beneath it -- that is how generated or
bulk-produced files (e.g. analysis/phase0/) stay documented without one heading per
file.

Exits 0 when clean, 1 on any drift, 2 on a usage/environment error.
No third-party dependencies.
"""
import pathlib
import re
import subprocess
import sys

FILES_MD = pathlib.Path("docs/FILES.md")
HEADING = re.compile(r"^###\s+(\S.*?)\s*$")


def repo_root() -> pathlib.Path:
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"error: not a git repository (or git unavailable): {exc}", file=sys.stderr)
        raise SystemExit(2)
    return pathlib.Path(out.stdout.strip())


def tracked_files(root: pathlib.Path) -> list[str]:
    out = subprocess.run(
        ["git", "ls-files"], cwd=root, capture_output=True, text=True, check=True
    )
    return sorted(p for p in out.stdout.splitlines() if p)


def manifest_entries(path: pathlib.Path) -> list[str]:
    """Parse `### path` headings. Strips backticks/bold that markdown may add."""
    entries = []
    for line in path.read_text(encoding="utf-8").splitlines():
        m = HEADING.match(line)
        if not m:
            continue
        entry = m.group(1).strip().strip("`").strip("*").strip()
        # Skip prose headings; a manifest entry always looks like a path.
        if " " in entry and "/" not in entry:
            continue
        entries.append(entry)
    return entries


def covers(entry: str, tracked: str) -> bool:
    if entry.endswith("/"):
        return tracked.startswith(entry)
    return tracked == entry


def main() -> int:
    root = repo_root()
    files_md = root / FILES_MD
    if not files_md.exists():
        print(f"error: {FILES_MD} not found at {files_md}", file=sys.stderr)
        return 2

    tracked = tracked_files(root)
    entries = manifest_entries(files_md)

    if not entries:
        print(f"error: no `### path` entries parsed from {FILES_MD}", file=sys.stderr)
        return 2

    undocumented = [f for f in tracked if not any(covers(e, f) for e in entries)]

    stale = []
    for e in entries:
        if e.endswith("/"):
            # A directory entry is stale only if nothing tracked lives under it.
            if not any(t.startswith(e) for t in tracked):
                stale.append(e)
        elif e not in tracked:
            stale.append(e)

    dupes = sorted({e for e in entries if entries.count(e) > 1})

    print(f"tracked files : {len(tracked)}")
    print(f"manifest entries: {len(entries)}")

    if not (undocumented or stale or dupes):
        print("\nOK - docs/FILES.md matches the repo.")
        return 0

    if undocumented:
        print(f"\nIn repo but MISSING from docs/FILES.md ({len(undocumented)}):")
        for f in undocumented:
            print(f"  + {f}")
    if stale:
        print(f"\nIn docs/FILES.md but NOT in repo ({len(stale)}):")
        for e in stale:
            print(f"  - {e}")
    if dupes:
        print(f"\nDuplicate entries in docs/FILES.md ({len(dupes)}):")
        for e in dupes:
            print(f"  ! {e}")
    print("\nFAIL - manifest drift.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
