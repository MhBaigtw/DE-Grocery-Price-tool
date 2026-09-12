#!/usr/bin/env python3
"""Proves check_light_parity.py fails when the light and full extracts differ.

The parity check is the only proof that the light refresh's filter drops nothing the extract
needs. So it must refuse every way two extracts can differ, and it must not refuse the one
legitimate difference: built_utc. Each case copies the committed extract twice, alters one
copy, and asserts the verdict.

Run: python scripts/test_check_light_parity.py
"""
from __future__ import annotations
import json, pathlib, shutil, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHECK = ROOT / "scripts" / "check_light_parity.py"
DATA = ROOT / "tool" / "data"


def verdict(full: pathlib.Path, light: pathlib.Path):
    p = subprocess.run([sys.executable, str(CHECK), "--full-dir", str(full), "--light-dir", str(light)],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    return p.returncode, p.stdout + p.stderr


def edit_json(path: pathlib.Path, fn) -> None:
    obj = json.loads(path.read_text(encoding="utf-8"))
    fn(obj)
    path.write_text(json.dumps(obj), encoding="utf-8")


def drop_product(d):
    edit_json(d / "products.json", lambda rows: rows.pop(len(rows) // 2))


def one_history_byte(d):
    b = bytearray((d / "history.json").read_bytes())
    i = b.index(b'"price":') + 8
    while not chr(b[i]).isdigit():
        i += 1
    b[i] = ord("9") if b[i] != ord("9") else ord("8")
    (d / "history.json").write_bytes(bytes(b))


def built_utc_only(d):
    edit_json(d / "meta.json", lambda m: m.__setitem__("built_utc", "2099-01-01T00:00:00+00:00"))


def meta_field(d):
    edit_json(d / "meta.json", lambda m: m.__setitem__("products_shipped", m["products_shipped"] - 1))


def other_snapshot(d):
    edit_json(d / "meta.json", lambda m: m.__setitem__("snapshot_id", "20990101T000000Z"))


def missing_file(d):
    (d / "history.json").unlink()


CASES = [
    # name, mutate the light copy, expected exit, text the output must contain
    ("identical extracts pass", lambda d: None, 0, "byte-identical"),
    ("built_utc alone is not a difference", built_utc_only, 0, "byte-identical"),
    ("a product the light filter dropped is refused", drop_product, 1, "1 record(s) only in full"),
    ("a single changed byte in history is refused", one_history_byte, 1, "history.json differs"),
    ("a changed meta.json field is refused", meta_field, 1, "products_shipped"),
    ("extracts from different snapshots are refused", other_snapshot, 1, "different snapshots"),
    ("a missing file is refused", missing_file, 1, "missing from the light extract"),
]


def main() -> int:
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except Exception:                                      # noqa: BLE001
            pass
    print("check_light_parity.py -- cases\n")
    ok = []
    for name, mutate, want, text in CASES:
        with tempfile.TemporaryDirectory() as td:
            full, light = pathlib.Path(td) / "full", pathlib.Path(td) / "light"
            shutil.copytree(DATA, full)
            shutil.copytree(DATA, light)
            mutate(light)
            rc, out = verdict(full, light)
            good = rc == want and text in out
            ok.append(good)
            print(f"  {'PASS' if good else 'FAIL'}  {name}")
            if not good:
                print(f"        expected exit {want} naming {text!r}; got exit {rc}")
                print("\n".join("        " + l for l in out.strip().splitlines()[-5:]))
    print(f"\n{sum(ok)} of {len(ok)} cases behaved correctly.")
    if not all(ok):
        print("FAIL - the parity check does not refuse something it must refuse.")
        return 1
    print("OK - every difference is refused, and built_utc alone is not treated as one.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
