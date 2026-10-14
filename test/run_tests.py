#!/usr/bin/env python3
"""Runs gfx2d's tests: test/api_check.py, and every program under
test/pure/ and test/headless/, its output compared with
test/expected/<dir>_<name>.out.

    python test/run_tests.py [--goose PATH] [--update] [name ...]

The compiler is --goose, else $GOOSE, else `goose` on the PATH. Programs run
in-process (`goose file.goose`) with GOOSE_GFX_HEADLESS=1, so nothing opens a
window. A headless program on a machine with no GPU device prints a line
starting "gfx: " and nothing else, and is reported skipped. --update writes
the outputs as the new expectations; review the diff before committing it.
"""

import argparse
import difflib
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
DIRS = ["pure", "headless"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--goose", default=os.environ.get("GOOSE") or shutil.which("goose"))
    ap.add_argument("--update", action="store_true")
    ap.add_argument("names", nargs="*", help="only tests whose name contains one of these")
    args = ap.parse_args()
    if not args.goose:
        sys.exit("run_tests: no goose compiler; pass --goose or set GOOSE")

    env = dict(os.environ, GOOSE_GFX_HEADLESS="1")
    passed = failed = skipped = 0
    if not args.names or any(n in "api_check" for n in args.names):
        r = subprocess.run([sys.executable, os.path.join(ROOT, "api_check.py")],
                           capture_output=True, text=True)
        if r.returncode == 0:
            passed += 1
            print("ok    api_check")
        else:
            failed += 1
            print("FAIL  api_check")
            print(r.stdout)
    for d in DIRS:
        for f in sorted(os.listdir(os.path.join(ROOT, d))):
            if not f.endswith(".goose"):
                continue
            name = f"{d}_{f[:-6]}"
            if args.names and not any(n in name for n in args.names):
                continue
            path = os.path.join(ROOT, d, f)
            r = subprocess.run([args.goose, path], capture_output=True, text=True, env=env,
                               cwd=ROOT)
            out = r.stdout
            if d == "headless" and out.startswith("gfx: ") and out.count("\n") <= 1:
                print(f"skip  {name}: {out.strip()}")
                skipped += 1
                continue
            expected_path = os.path.join(ROOT, "expected", name + ".out")
            if args.update and r.returncode == 0:
                with open(expected_path, "w", newline="\n") as fh:
                    fh.write(out)
            want = open(expected_path).read() if os.path.exists(expected_path) else None
            if r.returncode != 0 or out != want:
                failed += 1
                print(f"FAIL  {name} (exit {r.returncode})")
                if want is None:
                    print(f"      no {os.path.relpath(expected_path)}")
                else:
                    sys.stdout.writelines(difflib.unified_diff(
                        want.splitlines(True), out.splitlines(True), "expected", "got"))
                if r.returncode != 0:
                    print(r.stderr[-2000:])
            else:
                passed += 1
                print(f"ok    {name}")
    print(f"{passed} passed, {failed} failed, {skipped} skipped")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
