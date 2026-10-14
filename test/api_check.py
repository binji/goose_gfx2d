#!/usr/bin/env python3
"""Checks that text.goose declares exactly the functions src/text/text_api.h
lists in GS_GFX2D_TEXT_API, with as many parameters each, and that the
structs crossing between them have the same fields in the same order, with
the same sizes. goose_gfx's test/api_check.py does the same for its layers.

    python test/api_check.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

C_SIZES = {"int32_t": 4, "uint32_t": 4, "int64_t": 8, "uint8_t": 1, "float": 4}
GOOSE_SIZES = {"i32": 4, "u32": 4, "i64": 8, "u8": 1, "f32": 4, "bool": 1}
# The C structs and the Goose ones they are, by name.
STRUCTS = {
    "gs_gfx2d_font": "Font",
    "gs_gfx2d_font_metrics": "FontMetrics",
    "gs_gfx2d_glyph_metrics": "GlyphMetrics",
    "gs_gfx2d_glyph_bitmap": "GlyphBitmap",
}


def c_api(header):
    m = re.search(r"#define GS_GFX2D_TEXT_API\(X\)(.*?)\n\n", header, re.S)
    body = m.group(1).replace("\\\n", " ")
    out = {}
    for ret, name, args in re.findall(r"X\(\s*([\w ]+?)\s*,\s*(\w+)\s*,\s*\((.*?)\)\s*\)", body):
        params = [a.strip() for a in args.split(",") if a.strip() and a.strip() != "void"]
        out[name] = (ret, params)
    return out


def c_structs(header):
    out = {}
    for fields, name in re.findall(r"typedef struct \{(.*?)\} (\w+);", header, re.S):
        sizes = []
        for decl in re.sub(r"/\*.*?\*/", "", fields, flags=re.S).split(";"):
            decl = decl.strip()
            if not decl:
                continue
            typ, names = decl.split(None, 1)
            for n in names.split(","):
                sizes.append(C_SIZES.get(typ, 8))
        out[name] = sizes
    return out


def goose_api(src):
    out = {}
    for name, params in re.findall(r'extern "(\w+)" fn \w+\((.*?)\)', src, re.S):
        out[name] = [p for p in params.split(",") if p.strip()]
    return out


def goose_structs(src):
    out = {}
    for name, fields in re.findall(r"^struct (\w+) \{(.*?)\}", src, re.S | re.M):
        sizes = []
        for f in fields.split(","):
            f = f.strip()
            if not f:
                continue
            typ = f.split(":", 1)[1].split("=")[0].strip()
            sizes.append(GOOSE_SIZES.get(typ, 8))
        out[name] = sizes
    return out


def main():
    header = open(os.path.join(ROOT, "src", "text", "text_api.h")).read()
    goose = open(os.path.join(ROOT, "text.goose")).read()
    c, g = c_api(header), goose_api(goose)
    errors = []
    for name in sorted(set(c) | set(g)):
        if name not in g:
            errors.append(f"{name}: in text_api.h, not declared in text.goose")
        elif name not in c:
            errors.append(f"{name}: declared in text.goose, not in text_api.h")
        elif len(c[name][1]) != len(g[name]):
            errors.append(f"{name}: {len(c[name][1])} parameters in C, {len(g[name])} in Goose")
    cs, gs = c_structs(header), goose_structs(goose)
    for cname, gname in STRUCTS.items():
        if cs.get(cname) != gs.get(gname):
            errors.append(f"struct {gname}: fields {gs.get(gname)} in Goose, {cs.get(cname)} in C ({cname})")
    for e in errors:
        print(e)
    print(f"api_check: {len(c)} functions, {len(STRUCTS)} structs, {len(errors)} problems")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
