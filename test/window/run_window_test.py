#!/usr/bin/env python3
"""Runs gfx2d's showcase (test/window/gfx2d_showcase.goose) every way it can
-- in-process (JIT), and built ahead of time with the C compiler goose
finds -- checks that each run's own readback checks pass, and compares their
screenshots with each other.

    python test/window/run_window_test.py [--goose PATH] [--headless] [--frames N] [--keep DIR]

It opens a window per run unless --headless (GOOSE_GFX_HEADLESS=1, which
CI uses, and which needs only a GPU device). Screenshots should agree to
within rounding: the mean difference per channel must stay under 1/255
and no more than 0.1% of the pixels differ by more than 16. --keep keeps
the screenshots in DIR.
"""

import argparse
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
SHOWCASE = os.path.join(HERE, "gfx2d_showcase.goose")


def read_png(path):
    """The RGBA8 pixels of a PNG gfx saved: width, height and bytes."""
    data = open(path, "rb").read()
    pos = 8
    chunks = []
    w = h = 0
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
            if depth != 8 or ctype not in (2, 6):
                sys.exit(f"{path}: not an 8-bit RGB or RGBA PNG")
            channels = 4 if ctype == 6 else 3
        elif kind == b"IDAT":
            chunks.append(body)
        pos += 12 + n
    raw = zlib.decompress(b"".join(chunks))
    stride = w * channels
    out = bytearray()
    prev = bytearray(stride)
    i = 0
    for _ in range(h):
        f = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - channels] if x >= channels else 0
            b = prev[x]
            c = prev[x - channels] if x >= channels else 0
            if f == 1:
                line[x] = (line[x] + a) & 255
            elif f == 2:
                line[x] = (line[x] + b) & 255
            elif f == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        prev = line
        if channels == 4:
            out += line
        else:
            for x in range(w):
                out += line[x * 3:x * 3 + 3] + b"\xff"
    return w, h, bytes(out)


def compare(a, b):
    wa, ha, pa = read_png(a)
    wb, hb, pb = read_png(b)
    if (wa, ha) != (wb, hb):
        return False, f"sizes differ: {wa}x{ha} and {wb}x{hb}"
    total = 0
    far = 0
    for i in range(0, len(pa), 4):
        d = max(abs(pa[i + k] - pb[i + k]) for k in range(3))
        total += sum(abs(pa[i + k] - pb[i + k]) for k in range(3))
        if d > 16:
            far += 1
    mean = total / (wa * ha * 3)
    pixels = wa * ha
    ok = mean < 1.0 and far <= pixels * 0.001
    return ok, f"mean difference {mean:.3f}/255, {far} pixels differ by more than 16"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--goose", default=os.environ.get("GOOSE") or shutil.which("goose"))
    ap.add_argument("--headless", action="store_true")
    ap.add_argument("--frames", type=int, default=60)
    ap.add_argument("--keep")
    args = ap.parse_args()
    if not args.goose:
        sys.exit("run_window_test: no goose compiler; pass --goose or set GOOSE")
    env = dict(os.environ)
    if args.headless:
        env["GOOSE_GFX_HEADLESS"] = "1"
    tmp = args.keep or tempfile.mkdtemp()
    os.makedirs(tmp, exist_ok=True)
    runs = []
    failed = False

    def run(name, cmd):
        nonlocal failed
        out = os.path.join(tmp, name)
        os.makedirs(out, exist_ok=True)
        r = subprocess.run(cmd + ["--", "--frames", str(args.frames), "--out", out] if name == "jit"
                           else cmd + ["--frames", str(args.frames), "--out", out],
                           capture_output=True, text=True, env=env, cwd=tmp)
        lines = r.stdout.strip().splitlines()
        if lines and lines[0].startswith("gfx: "):
            print(f"skip  {name}: {lines[0]}")
            return
        summary = lines[-1] if lines else "(no output)"
        ok = r.returncode == 0 and summary == "checks: 0 failed"
        print(f"{'ok  ' if ok else 'FAIL'}  {name}: {summary}")
        if not ok:
            failed = True
            print("\n".join(l for l in lines if l.startswith("FAIL")) or r.stderr[-2000:])
        shot = os.path.join(out, "gfx2d_showcase.png")
        if os.path.exists(shot):
            runs.append((name, shot))

    run("jit", [args.goose, SHOWCASE])
    exe = os.path.join(tmp, "showcase")
    b = subprocess.run([args.goose, "build", "-o", exe, SHOWCASE], capture_output=True, text=True,
                       env=env)
    if b.returncode == 0:
        run("aot", [exe])
    else:
        failed = True
        print("FAIL  aot: build failed\n" + b.stderr[-2000:])
    for name, shot in runs[1:]:
        ok, what = compare(runs[0][1], shot)
        print(f"{'ok  ' if ok else 'FAIL'}  {runs[0][0]} vs {name}: {what}")
        failed |= not ok
    if args.keep:
        print(f"screenshots in {tmp}")
    else:
        shutil.rmtree(tmp, ignore_errors=True)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
