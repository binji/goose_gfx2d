// gfx2d's geometry: 2D affine transforms and rectangles. Plain Goose, no
// GPU (test/pure/transform.goose).
//
// Coordinates are pixels with y down, as gfx's screen and textures have
// them, so a positive angle turns clockwise on the screen. The builders here
// are nouns (translation, rotation, scaling, skewing) and return a matrix;
// the verbs in gfx2d.goose (translate, rotate, ...) change the current
// transform.

namespace gfx2d;

import std;
import vec;
import math;

// x' = a x + c y + tx, y' = b x + d y + ty: the columns (a, b) and (c, d)
// are where the x and y axes go.
struct Affine { a: f32, b: f32, c: f32, d: f32, tx: f32, ty: f32 }

let IDENTITY = Affine { 1.0, 0.0, 0.0, 1.0, 0.0, 0.0 };

struct Rect { x: f32, y: f32, w: f32, h: f32 }

fn translation(x: f64, y: f64) -> Affine { Affine { 1.0, 0.0, 0.0, 1.0, x as f32, y as f32 } }
fn translation(p: float2) -> Affine { translation(p.x, p.y) }
fn scaling(sx: f64, sy: f64) -> Affine { Affine { sx as f32, 0.0, 0.0, sy as f32, 0.0, 0.0 } }
fn scaling(s: f64) -> Affine { scaling(s, s) }
// `angle` radians, clockwise on the screen, about the origin.
fn rotation(angle: f64) -> Affine {
    let c = cos(angle) as f32;
    let s = sin(angle) as f32;
    Affine { c, s, -s, c, 0.0, 0.0 }
}
// About the point (cx, cy).
fn rotation_about(angle: f64, cx: f64, cy: f64) -> Affine {
    mul(translation(cx, cy), mul(rotation(angle), translation(-cx, -cy)))
}
// x leaning by `ax` radians as y grows, y by `ay` as x grows.
fn skewing(ax: f64, ay: f64) -> Affine { Affine { 1.0, tan(ay) as f32, tan(ax) as f32, 1.0, 0.0, 0.0 } }

// m after n: mul(m, n) applied to p is m applied to n applied to p.
fn mul(m: Affine, n: Affine) -> Affine {
    Affine { m.a * n.a + m.c * n.b, m.b * n.a + m.d * n.b,
             m.a * n.c + m.c * n.d, m.b * n.c + m.d * n.d,
             m.a * n.tx + m.c * n.ty + m.tx, m.b * n.tx + m.d * n.ty + m.ty }
}

fn apply(m: Affine, p: float2) -> float2 {
    float2 { m.a * p.x + m.c * p.y + m.tx, m.b * p.x + m.d * p.y + m.ty }
}
// A direction or size: the matrix without its translation.
fn apply_vector(m: Affine, v: float2) -> float2 {
    float2 { m.a * v.x + m.c * v.y, m.b * v.x + m.d * v.y }
}

fn determinant(m: Affine) -> f32 { m.a * m.d - m.b * m.c }

// The inverse, or false (and the identity) for a matrix that flattens the
// plane, such as a scaling by 0.
fn invert(m: Affine) -> Affine, bool {
    let det = determinant(m);
    if abs(det) < 0.000000000001 { return IDENTITY, false; }
    let k = 1.0 / det;
    let a = m.d * k;
    let b = -m.b * k;
    let c = -m.c * k;
    let d = m.a * k;
    return Affine { a, b, c, d, -(a * m.tx + c * m.ty), -(b * m.tx + d * m.ty) }, true;
}

// How long the matrix makes a unit along x and along y.
fn axis_scales(m: Affine) -> float2 {
    float2 { sqrt(m.a * m.a + m.b * m.b), sqrt(m.c * m.c + m.d * m.d) }
}
// The angle, in radians, the matrix turns the x axis to.
fn angle_of(m: Affine) -> f32 { atan2(m.b, m.a) }

// --- rectangles ------------------------------------------------------------------

// A Rect from any numbers, f64 included.
fn rect_of(x: f64, y: f64, w: f64, h: f64) -> Rect { Rect { x as f32, y as f32, w as f32, h as f32 } }
fn center(r: Rect) -> float2 { float2 { r.x + r.w * 0.5, r.y + r.h * 0.5 } }
fn contains(r: Rect, p: float2) -> bool {
    p.x >= r.x && p.y >= r.y && p.x < r.x + r.w && p.y < r.y + r.h
}
// Grown by `by` on every side; shrunk by a negative amount.
fn inflate(r: Rect, by: f64) -> Rect {
    let b = by as f32;
    Rect { r.x - b, r.y - b, r.w + 2.0 * b, r.h + 2.0 * b }
}
// Where two rectangles overlap, empty (w or h 0) where they do not.
fn intersect(r: Rect, s: Rect) -> Rect {
    let x0 = max(r.x, s.x);
    let y0 = max(r.y, s.y);
    let x1 = min(r.x + r.w, s.x + s.w);
    let y1 = min(r.y + r.h, s.y + s.h);
    Rect { x0, y0, max(0.0, x1 - x0), max(0.0, y1 - y0) }
}
// The smallest rectangle holding both.
fn union(r: Rect, s: Rect) -> Rect {
    let x0 = min(r.x, s.x);
    let y0 = min(r.y, s.y);
    Rect { x0, y0, max(r.x + r.w, s.x + s.w) - x0, max(r.y + r.h, s.y + s.h) - y0 }
}
// The bounds of r after m.
fn transformed_bounds(m: Affine, r: Rect) -> Rect {
    let p0 = apply(m, float2 { r.x, r.y });
    let p1 = apply(m, float2 { r.x + r.w, r.y });
    let p2 = apply(m, float2 { r.x, r.y + r.h });
    let p3 = apply(m, float2 { r.x + r.w, r.y + r.h });
    let x0 = min(min(p0.x, p1.x), min(p2.x, p3.x));
    let y0 = min(min(p0.y, p1.y), min(p2.y, p3.y));
    Rect { x0, y0, max(max(p0.x, p1.x), max(p2.x, p3.x)) - x0,
           max(max(p0.y, p1.y), max(p2.y, p3.y)) - y0 }
}

// How fit() maps one rectangle onto another.
let FIT_STRETCH = 0;    // fill it, aspect ratio changed
let FIT_CONTAIN = 1;    // all of src shows, centered, with bars along one axis
let FIT_COVER = 2;      // dst is all covered, centered, src cut along one axis

// The transform taking src onto dst.
fn fit(src: Rect, dst: Rect, mode: i64) -> Affine {
    var sx = dst.w / src.w;
    var sy = dst.h / src.h;
    if mode == FIT_CONTAIN { sx = min(sx, sy); sy = sx; }
    if mode == FIT_COVER { sx = max(sx, sy); sy = sx; }
    let c = center(dst);
    let s = center(src);
    Affine { sx, 0.0, 0.0, sy, c.x - s.x * sx, c.y - s.y * sy }
}
