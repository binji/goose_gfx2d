#!/usr/bin/env python3
"""Builds gfx2d's benchmarks (bench/bench.goose) ahead of time, runs them
headless, and writes bench/results.md: the environment, and a table of
each case's median frame times.

    python bench/run_bench.py [--goose PATH] [--frames N] [--jit] [--out FILE] [case ...]

The compiler is --goose, else $GOOSE, else `goose` on the PATH. --jit runs
the program in-process instead (`goose bench.goose`, -O1) rather than
building it (`goose build`, -O2). Cases: names, or parts of them; all by
default. bench/README.md says what each case measures and why.
"""

import argparse
import datetime
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# What each case draws, for the table.
CASES = {
    "empty": "an empty frame: clear, submit, wait",
    "circles": "10,000 solid circles",
    "mixed_shapes": "10,000 shapes of eight kinds, fills and outlines",
    "transformed": "10,000 rounded rects, each under translate, rotate and scale blocks",
    "gradients": "2,000 shapes, each with a gradient of its own stops",
    "shared_gradients": "10,000 circles sharing two gradients",
    "sprites": "10,000 sprites from one sheet",
    "sprites_alternating": "2,000 sprites, two textures taking turns",
    "path_fills": "1,000 star paths and 1,000 circle paths, filled",
    "big_path": "one 5,000-point noisy outline, filled",
    "self_crossing": "150 random points, about 5,000 crossings, even-odd",
    "chart": "20 polylines of 1,000 points, round joins",
    "dashed": "500 dashed circles",
    "text_page": "70 lines of 14px text, about 9,000 glyphs",
    "text_wrapped": "the same as one paragraph wrapped to 1,900px",
    "text_labels": "1,000 labels at random sizes, turned",
    "glyph_raster": "162 glyphs rasterized again from an empty atlas",
    "clips": "100 rounded-rect clips, 100 circles in each",
    "path_clips": "20 star-shaped path clips, 50 rects in each",
    "layers": "20 layers at half opacity, 50 circles in each",
    "blend_layers": "10 layers in screen, overlay, ... modes, 20 circles in each",
    "blur": "a blurred layer with a drop shadow, 200 rounded rects",
    "box_shadows": "2,000 box shadows under 2,000 rounded rects",
    "ui_scene": "60 panels: nine-slices, gradients, text, buttons, icons, charts",
    "ui_scene_msaa": "the same, multisampled 4 times",
}


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def first_line(cmd, pattern=None):
    try:
        out = run(cmd).stdout
    except OSError:
        return None
    for line in out.splitlines():
        if pattern is None or re.search(pattern, line):
            return line.strip()
    return None


def environment(goose, driver):
    cpu = platform.processor() or platform.machine()
    if os.path.exists("/proc/cpuinfo"):
        for line in open("/proc/cpuinfo"):
            if line.startswith("model name"):
                cpu = line.split(":", 1)[1].strip()
                break
    gpu = None
    dev = first_line(["vulkaninfo", "--summary"], r"deviceName")
    drv = first_line(["vulkaninfo", "--summary"], r"driverInfo")
    if dev:
        gpu = dev.split("=", 1)[1].strip()
        if drv:
            gpu += f" ({drv.split('=', 1)[1].strip()})"
    goose_dir = os.path.dirname(os.path.dirname(os.path.realpath(goose)))
    goose_rev = first_line(["git", "-C", goose_dir, "rev-parse", "--short", "HEAD"])
    own_rev = first_line(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"])
    dirty = run(["git", "-C", ROOT, "status", "--porcelain", "--", "."]).stdout.strip()
    return [
        ("CPU", cpu),
        ("GPU", gpu or "unknown"),
        ("Backend", driver),
        ("OS", f"{platform.system()} {platform.release()}"),
        ("Goose", goose_rev or "unknown"),
        ("gfx2d", (own_rev or "unknown") + (" (with local changes)" if dirty else "")),
    ]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--goose", default=os.environ.get("GOOSE") or shutil.which("goose"))
    ap.add_argument("--frames", type=int, default=60)
    ap.add_argument("--jit", action="store_true")
    ap.add_argument("--out", default=os.path.join(HERE, "results.md"))
    ap.add_argument("cases", nargs="*")
    args = ap.parse_args()
    if not args.goose:
        sys.exit("run_bench: no goose compiler; pass --goose or set GOOSE")
    env = dict(os.environ, GOOSE_GFX_HEADLESS="1")
    src = os.path.join(HERE, "bench.goose")
    prog_args = ["--frames", str(args.frames)] + args.cases
    with tempfile.TemporaryDirectory() as tmp:
        if args.jit:
            cmd = [args.goose, src, "--"] + prog_args
            mode = "JIT, in-process (`goose bench.goose`, -O1)"
        else:
            exe = os.path.join(tmp, "bench")
            b = run([args.goose, "build", "-o", exe, src], env=env)
            if b.returncode != 0:
                sys.exit("run_bench: build failed\n" + b.stderr[-3000:])
            cmd = [exe] + prog_args
            mode = "ahead of time (`goose build`, -O2)"
        print("running:", " ".join(cmd), file=sys.stderr)
        r = run(cmd, env=env, cwd=tmp)
    if r.returncode != 0:
        sys.exit("run_bench: the benchmark failed\n" + r.stdout[-2000:] + r.stderr[-3000:])
    if r.stdout.startswith("gfx: "):
        sys.exit("run_bench: " + r.stdout.strip())
    header = r.stdout.splitlines()[0]
    driver = re.search(r", (\w+), ", header)
    rows = []
    for line in r.stdout.splitlines():
        if line.startswith("case "):
            name, frames, rec, end, gpu, inst, tris, draws, nbytes, npasses = line.split()[1:11]
            rows.append((name, float(rec), float(end), float(gpu), int(inst), int(tris), int(draws),
                         int(nbytes), int(npasses)))

    lines = [
        "# gfx2d benchmark results",
        "",
        f"Generated by `bench/run_bench.py` on {datetime.datetime.now():%Y-%m-%d %H:%M}. "
        "Do not edit by hand. The cases are `bench/bench.goose`; `bench/README.md` says what "
        "each one is for and how to read the columns.",
        "",
        "## Environment",
        "",
        "| | |",
        "|---|---|",
    ]
    for k, v in environment(args.goose, driver.group(1) if driver else "unknown"):
        lines.append(f"| {k} | {v} |")
    lines += [
        f"| Build | {mode} |",
        f"| Frames | 1920x1080, an RGBA8 target, headless; medians of {args.frames} frames after 5 untimed |",
        "",
        "## Results",
        "",
        "Milliseconds per frame. *record* is the draw calls, *end* is `end()` "
        "(uploads and the pass), both CPU; *gpu* is `gfx::flush()`, submitting and "
        "waiting for the GPU.",
        "",
        "| case | draws what | record | end | gpu | total | instances | triangles | draw calls | passes | uploaded |",
        "|---|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|",
    ]
    for name, rec, end, gpu, inst, tris, draws, nbytes, npasses in rows:
        lines.append(f"| `{name}` | {CASES.get(name, '')} | {rec:.2f} | {end:.2f} | {gpu:.2f} | "
                     f"{rec + end + gpu:.2f} | {inst:,} | {tris:,} | {draws:,} | {npasses} | "
                     f"{nbytes / 1e6:.1f} MB |")
    lines.append("")
    with open(args.out, "w", newline="\n") as fh:
        fh.write("\n".join(lines))
    print("\n".join(lines[-len(rows) - 3:]))
    print(f"wrote {os.path.relpath(args.out)}", file=sys.stderr)


if __name__ == "__main__":
    main()
