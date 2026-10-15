// gfx2d's paths: building them, flattening their curves, filling them by
// the nonzero or even-odd rule, and stroking them with joins, caps and
// dashes. Plain Goose, no GPU (test/pure/path.goose); gfx2d.goose draws the
// triangles this makes.
//
//   var p = gfx2d::Path {};
//   p.move_to(10, 10);
//   p.cubic_to(40, 0, 60, 80, 90, 40);
//   p.line_to(90, 90);
//   p.close();
//   gfx2d::fill(p, gfx2d::ORANGE);
//   gfx2d::stroke(p, 3, gfx2d::BLACK);
//
// A fill becomes triangles by bands: the path's edges are cut at every
// vertex's y and every crossing, and in each band the fill rule picks the
// spans between edges, each a trapezoid. That handles holes, any
// self-intersection and both fill rules in one way. A convex outline, the
// commonest case, is a fan instead. Either gets a fringe a pixel wide along
// its outline, whose alpha falls to 0, for antialiasing.
//
// A stroke becomes an outline (one per open subpath, two per closed one),
// filled by the nonzero rule: so where a stroke crosses itself or its
// joins overlap, it is drawn once, and translucent strokes do not darken
// there.

namespace gfx2d;

import std;
import vec;
import math;
import transform;

enum PathEl {
    Move { p: float2 },
    Line { p: float2 },
    Quad { c: float2, p: float2 },
    Cubic { c1: float2, c2: float2, p: float2 },
    Close,
}

struct Path { els: PathEl[>..] = [] }

// Fill rules.
let NONZERO = 0;
let EVEN_ODD = 1;

// Stroke joins; the caps are gfx2d.goose's CAP_BUTT, CAP_ROUND, CAP_SQUARE.
let JOIN_MITER = 0;
let JOIN_ROUND = 1;
let JOIN_BEVEL = 2;

let MAX_DASHES = 8;

struct Stroke {
    width: f32 = 1.0,
    join: i32 = 0,                  // JOIN_MITER
    cap: i32 = 0,                   // CAP_BUTT
    miter_limit: f32 = 4.0,         // a miter longer than this many half widths is beveled
    dash: f32[..8] = [],            // on, off, on, off, ... lengths; empty: solid
    dash_offset: f32 = 0.0,         // how far into the pattern the path starts
    pixels: bool = false,           // width and dashes in pixels, whatever the transform
}

// --- building ----------------------------------------------------------------------

fn pt(x: f64, y: f64) -> float2 { float2 { x as f32, y as f32 } }

fn move_to(p: Path&, x: f64, y: f64) { p.els.push(PathEl.Move { pt(x, y) }); }
fn line_to(p: Path&, x: f64, y: f64) { p.els.push(PathEl.Line { pt(x, y) }); }
fn quad_to(p: Path&, cx: f64, cy: f64, x: f64, y: f64) {
    p.els.push(PathEl.Quad { pt(cx, cy), pt(x, y) });
}
fn cubic_to(p: Path&, c1x: f64, c1y: f64, c2x: f64, c2y: f64, x: f64, y: f64) {
    p.els.push(PathEl.Cubic { pt(c1x, c1y), pt(c2x, c2y), pt(x, y) });
}
fn close(p: Path&) { p.els.push(PathEl.Close); }
fn clear(p: Path&) { p.els.resize(0); }
fn is_empty(p: const Path&) -> bool { p.els.len == 0 }

// Where the path's pen is: the end of its last element; (0, 0) if none.
fn current_point(p: const Path&) -> float2 {
    var i = p.els.len;
    var closing = false;
    while i > 0 {
        i--;
        match p.els[i] {
            Move m => { return m.p; },
            Line l => { if !closing { return l.p; } },
            Quad q => { if !closing { return q.p; } },
            Cubic c => { if !closing { return c.p; } },
            Close => { closing = true; },
        }
    }
    float2_0
}
fn is_drawing(p: const Path&) -> bool {
    p.els.len > 0 && (match p.els[p.els.len - 1] { Close => false, _ => true })
}

// An elliptical arc about (cx, cy) from angle a0 to a1 (radians, clockwise
// on the screen; a1 < a0 goes counterclockwise), as cubics of at most a
// quarter turn each. It is joined to the path by a line from the pen, or
// starts a subpath where none is being drawn.
fn arc(p: Path&, cx: f64, cy: f64, rx: f64, ry: f64, a0: f64, a1: f64) {
    let start = pt(cx + rx * cos(a0), cy + ry * sin(a0));
    if is_drawing(p) { p.line_to(start.x, start.y); } else { p.move_to(start.x, start.y); }
    let sweep = clamp(a1 - a0, -TAU, TAU);
    let n = max(1, ceil(abs(sweep) / (PI / 2) - 0.000001) as i64);
    let step = sweep / n;
    let k = 4.0 / 3.0 * tan(step / 4);
    for i in n {
        let s = a0 + step * i;
        let e = s + step;
        p.cubic_to(cx + rx * (cos(s) - k * sin(s)), cy + ry * (sin(s) + k * cos(s)),
                   cx + rx * (cos(e) + k * sin(e)), cy + ry * (sin(e) - k * cos(e)),
                   cx + rx * cos(e), cy + ry * sin(e));
    }
}
fn arc(p: Path&, cx: f64, cy: f64, r: f64, a0: f64, a1: f64) { p.arc(cx, cy, r, r, a0, a1); }

// Closed shapes, each a subpath of its own.
fn rect(p: Path&, x: f64, y: f64, w: f64, h: f64) {
    p.move_to(x, y);
    p.line_to(x + w, y);
    p.line_to(x + w, y + h);
    p.line_to(x, y + h);
    p.close();
}
fn rounded_rect(p: Path&, x: f64, y: f64, w: f64, h: f64, r: f64) {
    let rr = clamp(r, 0.0, min(abs(w), abs(h)) * 0.5);
    if rr <= 0.0 {
        p.rect(x, y, w, h);
        return;
    }
    p.move_to(x + rr, y);
    p.arc(x + w - rr, y + rr, rr, -PI / 2, 0);
    p.arc(x + w - rr, y + h - rr, rr, 0, PI / 2);
    p.arc(x + rr, y + h - rr, rr, PI / 2, PI);
    p.arc(x + rr, y + rr, rr, PI, PI * 1.5);
    p.close();
}
fn ellipse(p: Path&, cx: f64, cy: f64, rx: f64, ry: f64) {
    p.move_to(cx + rx, cy);
    p.arc(cx, cy, rx, ry, 0, TAU);
    p.close();
}
fn circle(p: Path&, cx: f64, cy: f64, r: f64) { p.ellipse(cx, cy, r, r); }
// Through the points in order; closed, or left open for a polyline.
fn polygon(p: Path&, points: const float2[:], closed: bool = true) {
    for q, i in points {
        if i == 0 { p.move_to(q.x, q.y); } else { p.line_to(q.x, q.y); }
    }
    if closed && points.len > 0 { p.close(); }
}
// n corners on the circle of radius r, the first at `angle`.
fn regular_polygon(p: Path&, cx: f64, cy: f64, r: f64, n: i64, angle: f64 = -PI / 2) {
    for i in n {
        let a = angle + TAU * i / n;
        if i == 0 { p.move_to(cx + r * cos(a), cy + r * sin(a)); }
        else { p.line_to(cx + r * cos(a), cy + r * sin(a)); }
    }
    p.close();
}
// n points at radius `outer`, the corners between them at `inner`.
fn star(p: Path&, cx: f64, cy: f64, n: i64, outer: f64, inner: f64, angle: f64 = -PI / 2) {
    for i in 2 * n {
        let a = angle + PI * i / n;
        let r = if i % 2 == 0 { outer } else { inner };
        if i == 0 { p.move_to(cx + r * cos(a), cy + r * sin(a)); }
        else { p.line_to(cx + r * cos(a), cy + r * sin(a)); }
    }
    p.close();
}

// Every point of the path moved by m.
fn transform(p: Path&, m: Affine) {
    for &e in p.els {
        match e {
            Move v => { e = PathEl.Move { apply(m, v.p) }; },
            Line v => { e = PathEl.Line { apply(m, v.p) }; },
            Quad v => { e = PathEl.Quad { apply(m, v.c), apply(m, v.p) }; },
            Cubic v => { e = PathEl.Cubic { apply(m, v.c1), apply(m, v.c2), apply(m, v.p) }; },
            Close => {},
        }
    }
}

// The bounds of the path's points, control points included.
fn bounds(p: const Path&) -> Rect {
    var lo = float2 { 1e30, 1e30 };
    var hi = float2 { -1e30, -1e30 };
    fn take(q: float2) {
        lo = float2 { min(lo.x, q.x), min(lo.y, q.y) };
        hi = float2 { max(hi.x, q.x), max(hi.y, q.y) };
    }
    for e in p.els {
        match e {
            Move v => take(v.p),
            Line v => take(v.p),
            Quad v => { take(v.c); take(v.p); },
            Cubic v => { take(v.c1); take(v.c2); take(v.p); },
            Close => {},
        }
    }
    if lo.x > hi.x { return Rect { 0.0, 0.0, 0.0, 0.0 }; }
    Rect { lo.x, lo.y, hi.x - lo.x, hi.y - lo.y }
}

// --- flattening ----------------------------------------------------------------------

// A run of points in a flattened path: pts[first .. first + count].
// A stroke's outline marks up to two runs of edges (edge i runs from point i
// to the next), skip_a_n from skip_a and skip_b_n from skip_b, as inside the
// stroke, where one piece of it meets another, to get no antialiasing
// fringe; and numbers its pieces, each tessellated alone.
struct Contour { first: i64, count: i64, closed: bool, skip_a: i64 = 0, skip_a_n: i64 = 0,
                 skip_b: i64 = 0, skip_b_n: i64 = 0, group: i64 = 0 }

fn has_inner_edges(c: Contour) -> bool { c.skip_a_n > 0 || c.skip_b_n > 0 }
fn is_inner_edge(c: Contour, i: i64) -> bool {
    (i >= c.skip_a && i < c.skip_a + c.skip_a_n) || (i >= c.skip_b && i < c.skip_b + c.skip_b_n)
}

// Straight-line segments for the path after m, none further than
// `tolerance` from the curve: appended to pts and contours. Bézier curves
// keep their shape under an affine transform, so the control points are
// transformed and the curve flattened in the transformed space, where the
// tolerance is measured. Repeated points are dropped.
fn flatten(path: const Path&, m: Affine, tolerance: f32, pts: float2[>..<]&, contours: Contour[>..<]&) {
    var start = pts.len;
    var pen = float2_0;
    fn end_contour(closed: bool) {
        if pts.len - start >= 1 {
            contours.push(Contour { first: start, count: pts.len - start, closed: closed });
        } else {
            pts.resize(start);
        }
        start = pts.len;
    }
    fn add(q: float2) {
        if pts.len > start {
            let last = pts[pts.len - 1];
            if abs(last.x - q.x) < 0.00001 && abs(last.y - q.y) < 0.00001 { return; }
        }
        pts.push(q);
    }
    // Wang's formula: the segments a curve of this degree needs.
    fn segments(dd: f32, factor: f32) -> i64 {
        clamp(ceil(sqrt(factor * dd / tolerance)) as i64, 1, 500)
    }
    for e in path.els {
        match e {
            Move v => {
                end_contour(false);
                pen = apply(m, v.p);
                add(pen);
            },
            Line v => {
                if pts.len == start { add(pen); }
                pen = apply(m, v.p);
                add(pen);
            },
            Quad v => {
                if pts.len == start { add(pen); }
                let p0 = pen;
                let c = apply(m, v.c);
                let p1 = apply(m, v.p);
                let n = segments(length(p0 - c * float2 { 2, 2 } + p1), 0.25);
                for i in 1..n + 1 {
                    let t: f32 = i / (n as f32);
                    let u = 1.0 - t;
                    add(p0 * float2 { u * u, u * u } + c * float2 { 2 * u * t, 2 * u * t } +
                        p1 * float2 { t * t, t * t });
                }
                pen = p1;
            },
            Cubic v => {
                if pts.len == start { add(pen); }
                let p0 = pen;
                let c1 = apply(m, v.c1);
                let c2 = apply(m, v.c2);
                let p1 = apply(m, v.p);
                let dd = max(length(p0 - c1 * float2 { 2, 2 } + c2), length(c1 - c2 * float2 { 2, 2 } + p1));
                let n = segments(dd, 0.75);
                for i in 1..n + 1 {
                    let t: f32 = i / (n as f32);
                    let u = 1.0 - t;
                    let a = u * u * u;
                    let b = 3 * u * u * t;
                    let c = 3 * u * t * t;
                    let d = t * t * t;
                    add(p0 * float2 { a, a } + c1 * float2 { b, b } + c2 * float2 { c, c } +
                        p1 * float2 { d, d });
                }
                pen = p1;
            },
            Close => {
                // A closed contour does not repeat its first point at its end.
                if pts.len - start >= 2 {
                    let first = pts[start];
                    let last = pts[pts.len - 1];
                    if abs(last.x - first.x) < 0.00001 && abs(last.y - first.y) < 0.00001 {
                        pts.resize(pts.len - 1);
                    }
                    pen = first;
                }
                end_contour(true);
            },
        }
    }
    end_contour(false);
}

// --- filling ---------------------------------------------------------------------------

// A vertex of a tessellated path: where it is, in the space it was
// flattened in, and the coverage there (1 inside, falling to 0 across the
// fringe).
struct TessVertex { p: float2, alpha: f32 }

fn perp(d: float2) -> float2 { float2 { d.y, -d.x } }
fn cross2(a: float2, b: float2) -> f32 { a.x * b.y - a.y * b.x }
fn unit(d: float2) -> float2 {
    let l = length(d);
    if l > 0.0 { d / float2 { l, l } } else { float2_0 }
}

fn filled(winding: i64, rule: i64) -> bool {
    if rule == EVEN_ODD { winding % 2 != 0 } else { winding != 0 }
}

// The winding number of the closed contours about q.
fn winding_at(pts: const float2[:], contours: const Contour[:], q: float2) -> i64 {
    var w = 0;
    for c in contours {
        for i in c.count {
            let a = pts[c.first + i];
            let b = pts[c.first + (i + 1) % c.count];
            if a.y <= q.y {
                if b.y > q.y && cross2(b - a, q - a) > 0.0 { w++; }
            } else if b.y <= q.y && cross2(b - a, q - a) < 0.0 {
                w--;
            }
        }
    }
    w
}

// Whether q is inside the path, by `rule`.
fn contains(path: const Path&, q: float2, rule: i64 = NONZERO) -> bool {
    var pts: float2[>..<] = [];
    var contours: Contour[>..<] = [];
    flatten(path, IDENTITY, 0.1, pts, contours);
    filled(winding_at(pts, contours, q), rule)
}

// The signed area of a contour: positive when it turns clockwise on the
// screen (y down).
fn signed_area(pts: const float2[:], c: Contour) -> f32 {
    var a: f32 = 0.0;
    for i in c.count {
        let p = pts[c.first + i];
        let q = pts[c.first + (i + 1) % c.count];
        a += p.x * q.y - q.x * p.y;
    }
    a * 0.5
}

// Whether a closed contour is convex: every corner turns the same way, and
// it turns once around, not twice as a pentagram does.
fn is_convex(pts: const float2[:], c: Contour) -> bool {
    if c.count < 3 { return false; }
    var sign = 0;
    var turned: f32 = 0.0;
    for i in c.count {
        let a = pts[c.first + i];
        let b = pts[c.first + (i + 1) % c.count];
        let d = pts[c.first + (i + 2) % c.count];
        let e0 = b - a;
        let e1 = d - b;
        let x = cross2(e0, e1);
        if abs(x) > 0.000001 * (length(e0) * length(e1) + 0.000001) {
            let s = if x > 0.0 { 1 } else { -1 };
            if sign == 0 { sign = s; } else if s != sign { return false; }
        }
        turned += atan2(x, dot(e0, e1));
    }
    abs(abs(turned) - TAU) < 0.01
}

// For each point of a closed contour, the direction its fringe goes out:
// the miter of its edges' normals, pointing away from the fill, of length
// such that it moves each edge by 1 (capped at 4 where corners are sharp).
// `side` is fill_side's: +1 when the fill is on the edges' left, -1 on
// their right.
fn fringe_normal(pts: const float2[:], c: Contour, i: i64, side: f32) -> float2 {
    let p = pts[c.first + i];
    let prev = pts[c.first + (i + c.count - 1) % c.count];
    let next = pts[c.first + (i + 1) % c.count];
    let n0 = perp(unit(p - prev));
    let n1 = perp(unit(next - p));
    let k = 1.0 + dot(n0, n1);
    var m = if k > 0.125 { (n0 + n1) / float2 { k, k } } else { unit(n0 + n1) * float2 { 4, 4 } };
    if k <= 0.125 && length(m) < 0.5 { m = n0; }
    // perp() is the left normal, so the fill's side, negated, is out.
    m * float2 { -side, -side }
}

// Which side of contour c the fill is on, by testing just beside the
// middle of its longest edge: +1 for the left of its direction, -1 for the
// right, 0 for neither (an edge with fill or with none on both sides).
fn fill_side(pts: const float2[:], contours: const Contour[:], c: Contour, rule: i64,
             scale: f32) -> f32 {
    var best = 0;
    var best_len: f32 = -1.0;
    for i in c.count {
        let l = length(pts[c.first + (i + 1) % c.count] - pts[c.first + i]);
        if l > best_len { best_len = l; best = i; }
    }
    let a = pts[c.first + best];
    let b = pts[c.first + (best + 1) % c.count];
    let mid = (a + b) * float2 { 0.5, 0.5 };
    let off = perp(unit(b - a)) * float2 { 0.01 * scale, 0.01 * scale };
    let left = filled(winding_at(pts, contours, mid + off), rule);
    let right = filled(winding_at(pts, contours, mid - off), rule);
    if left && !right { return 1.0; }
    if right && !left { return -1.0; }
    0.0
}

fn add_vertex(out: TessVertex[>..<]&, p: float2, alpha: f32) -> u32 {
    out.push(TessVertex { p, alpha });
    (out.len - 1) as u32
}
fn add_quad(idx: u32[>..<]&, a: u32, b: u32, c: u32, d: u32) {
    idx.append([a, b, c, a, c, d]);
}

// An edge going down, from y0 to y1 > y0, with the direction the contour
// went it: +1 down, -1 up.
struct Edge { x0: f32, y0: f32, x1: f32, y1: f32, dir: i32, id: i32 }
fn x_at(e: Edge, y: f32) -> f32 { e.x0 + (e.x1 - e.x0) * (y - e.y0) / (e.y1 - e.y0) }

// An edge across one band: x at its top and bottom.
struct Crossing { xa: f32, xb: f32, dir: i32, edge: i32 }

// A trapezoid still growing down: between two edges, from `top`, for as
// long as the same two edges bound a span in each band.
struct OpenTrap { left: i32, right: i32, top: f32, seen: bool }

var tess_edges: Edge[>..<] = [];
var tess_ys: f32[>..<] = [];
var tess_active: Edge[>..<] = [];
var tess_band: Crossing[>..<] = [];
var tess_open: OpenTrap[>..<] = [];

// Past this much work (edges looked at, band after band) or this many
// vertices out, a fill gives up, drawing what it has, rather than take
// minutes or run out of memory: what a path of thousands of points crossing
// each other everywhere would need. Ordinary paths, a 5,000-point outline
// included, need a small fraction of it. tess_gave_up says it did.
let MAX_WORK = 20000000;
let MAX_VERTICES = 4000000;
var tess_gave_up = false;

// The closed contours' fill by `rule`, as triangles appended to out and
// idx. `fringe` is how wide the antialiasing fringe is, in the units of pts
// (a pixel; 0 for none).
fn fill_triangles(pts: const float2[:], contours: const Contour[:], rule: i64, fringe: f32,
                  out: TessVertex[>..<]&, idx: u32[>..<]&) {
    var live = 0;
    for c in contours { if c.count >= 3 { live++; } }
    if live == 0 { return; }
    if live == 1 {
        for c in contours {
            // Not one with inner edges: the convex fill moves its outline in,
            // which would leave a gap where it meets another piece.
            if c.count >= 3 && !has_inner_edges(c) && is_convex(pts, c) {
                fill_convex(pts, c, fringe, out, idx);
                return;
            }
        }
    }
    fill_bands(pts, contours, rule, out, idx);
    if fringe > 0.0 {
        let half = fringe * 0.5;
        for c in contours {
            if c.count < 3 { continue; }
            let side = fill_side(pts, contours, c, rule, fringe);
            if side == 0.0 { continue; }
            // From the edge, where the fill's own triangles stop and a pixel
            // is half covered, to half a pixel out, uncovered.
            let base = out.len as u32;
            for i in c.count {
                let p = pts[c.first + i];
                let n = fringe_normal(pts, c, i, side);
                add_vertex(out, p, 0.5);
                add_vertex(out, p + n * float2 { half, half }, 0.0);
            }
            for i in c.count {
                if is_inner_edge(c, i) { continue; }
                let j = (i + 1) % c.count;
                add_quad(idx, base + 2 * i as u32, base + 2 * j as u32, base + 2 * j as u32 + 1,
                         base + 2 * i as u32 + 1);
            }
        }
    }
}

// A convex contour: a fan over its outline moved in by half the fringe,
// and the fringe from there (covered) to half out (uncovered).
fn fill_convex(pts: const float2[:], c: Contour, fringe: f32, out: TessVertex[>..<]&,
               idx: u32[>..<]&) {
    // Clockwise on the screen (positive area) has the fill on the right.
    let side: f32 = if signed_area(pts, c) > 0.0 { -1.0 } else { 1.0 };
    let half = fringe * 0.5;
    let base = out.len as u32;
    for i in c.count {
        let p = pts[c.first + i];
        let n = if fringe > 0.0 { fringe_normal(pts, c, i, side) } else { float2_0 };
        add_vertex(out, p - n * float2 { half, half }, 1.0);
        if fringe > 0.0 { add_vertex(out, p + n * float2 { half, half }, 0.0); }
    }
    let stride: u32 = if fringe > 0.0 { 2 } else { 1 };
    for i in 1..c.count - 1 {
        idx.append([base, base + stride * i as u32, base + stride * (i + 1) as u32]);
    }
    if fringe > 0.0 {
        for i in c.count {
            let j = (i + 1) % c.count;
            add_quad(idx, base + 2 * i as u32, base + 2 * j as u32, base + 2 * j as u32 + 1,
                     base + 2 * i as u32 + 1);
        }
    }
}

// Any fill: in bands between the ys where edges start, end or cross, the
// spans the rule fills, as trapezoids. Exact, with no fringe of its own.
fn fill_bands(pts: const float2[:], contours: const Contour[:], rule: i64,
              out: TessVertex[>..<]&, idx: u32[>..<]&) {
    tess_edges.resize(0);
    tess_ys.resize(0);
    for c in contours {
        if c.count < 3 { continue; }
        for i in c.count {
            let a = pts[c.first + i];
            let b = pts[c.first + (i + 1) % c.count];
            if a.y == b.y { continue; }
            if a.y < b.y { tess_edges.push(Edge { a.x, a.y, b.x, b.y, 1, 0 }); }
            else { tess_edges.push(Edge { b.x, b.y, a.x, a.y, -1, 0 }); }
            tess_ys.push(a.y);
        }
    }
    if tess_edges.len == 0 { return; }
    sort(tess_edges) { a, b => a.y0 < b.y0 };
    for &e, i in tess_edges { e.id = i as i32; }
    sort(tess_ys);
    tess_active.resize(0);
    tess_open.resize(0);
    var work = 0;
    var next = 0;
    var k = 0;
    while k < tess_ys.len {
        let y_top = tess_ys[k];
        // The next distinct y below.
        var k2 = k + 1;
        while k2 < tess_ys.len && tess_ys[k2] <= y_top { k2++; }
        if k2 >= tess_ys.len { break; }
        let y_end = tess_ys[k2];
        k = k2;
        // Edges starting by now join; ones ended leave.
        while next < tess_edges.len && tess_edges[next].y0 <= y_top {
            tess_active.push(tess_edges[next]);
            next++;
        }
        var w = 0;
        for e in tess_active {
            if e.y1 > y_top {
                tess_active[w] = e;
                w++;
            }
        }
        tess_active.resize(w);
        var ya = y_top;
        while ya < y_end {
            if work > MAX_WORK || out.len > MAX_VERTICES {
                tess_gave_up = true;
                close_traps(ya, out, idx);
                return;
            }
            // The band, cut short at a crossing until none is left in it.
            // Sorted by x at its middle, which orders a band without
            // crossings the same everywhere in it; where that order differs
            // at the top or bottom of the band, two neighbors in it cross.
            var yb = y_end;
            loop {
                work += tess_active.len + 1;
                tess_band.resize(0);
                for e in tess_active {
                    tess_band.push(Crossing { x_at(e, ya), x_at(e, yb), e.dir, e.id });
                }
                sort(tess_band) { a, b => a.xa + a.xb < b.xa + b.xb };
                var cut = yb;
                for i in 0..tess_band.len - 1 {
                    let da = tess_band[i + 1].xa - tess_band[i].xa;
                    let db = tess_band[i + 1].xb - tess_band[i].xb;
                    if (da < -0.0001 && db > 0.0001) || (da > 0.0001 && db < -0.0001) {
                        let y = ya + (yb - ya) * da / (da - db);
                        if y > ya + 0.0001 && y < cut - 0.0001 { cut = y; }
                    }
                }
                if cut >= yb { break; }
                yb = cut;
            }
            band_spans(rule, ya, out, idx);
            ya = yb;
        }
    }
    close_traps(tess_ys[tess_ys.len - 1], out, idx);
}

// The band from ya's filled spans: each continues the open trapezoid of
// the same two edges, or starts one; open trapezoids no span continued end
// at ya.
fn band_spans(rule: i64, ya: f32, out: TessVertex[>..<]&, idx: u32[>..<]&) {
    for &t in tess_open { t.seen = false; }
    var winding = 0;
    var left: i32 = -1;
    for c in tess_band {
        let was = filled(winding, rule);
        winding += c.dir;
        let now = filled(winding, rule);
        if !was && now {
            left = c.edge;
        } else if was && !now {
            var found = false;
            for &t in tess_open {
                if t.left == left && t.right == c.edge {
                    t.seen = true;
                    found = true;
                    break;
                }
            }
            if !found { tess_open.push(OpenTrap { left, c.edge, ya, true }); }
        }
    }
    // The ones not continued, out; the rest kept, in order.
    var w = 0;
    for t in tess_open {
        if t.seen {
            tess_open[w] = t;
            w++;
        } else {
            emit_trap(t, ya, out, idx);
        }
    }
    tess_open.resize(w);
}

fn close_traps(y: f32, out: TessVertex[>..<]&, idx: u32[>..<]&) {
    for t in tess_open { emit_trap(t, y, out, idx); }
    tess_open.resize(0);
}

// A trapezoid between its edges from its top to y.
fn emit_trap(t: OpenTrap, y: f32, out: TessVertex[>..<]&, idx: u32[>..<]&) {
    if y <= t.top { return; }
    let l = tess_edges[t.left];
    let r = tess_edges[t.right];
    let lt = x_at(l, t.top);
    let rt = x_at(r, t.top);
    let lb = x_at(l, y);
    let rb = x_at(r, y);
    if rt - lt <= 0.000001 && rb - lb <= 0.000001 { return; }
    let a = add_vertex(out, float2 { lt, t.top }, 1.0);
    let b = add_vertex(out, float2 { rt, t.top }, 1.0);
    let d = add_vertex(out, float2 { rb, y }, 1.0);
    let e = add_vertex(out, float2 { lb, y }, 1.0);
    add_quad(idx, a, b, d, e);
}

// --- stroking --------------------------------------------------------------------------

// A stroke longer than this many segments is outlined in pieces of about
// this many, each tessellated alone: the band tessellator's work grows with
// the square of an outline's length, which a chart's thousand-point line, as
// one outline, makes ruinous. Pieces meet across the middle of a segment,
// where both have the same butt end, so they leave no gap; the longest
// segment in the second half of each piece is the one cut, and they do not
// overlap either unless even it is too short for the stroke's width (shorter
// than about the width, with sharp joins beside it), which only a
// translucent stroke shows.
let STROKE_CHUNK = 16;

var piece_pts: float2[>..<] = [];

// The outline of a stroke of `half` half width along the contours, as closed
// contours appended to out_pts and out_contours, to be filled by the
// nonzero rule, each group of them (Contour.group) on its own. Round joins
// and caps are flattened to `tolerance`.
fn stroke_outline(pts: const float2[:], contours: const Contour[:], half: f32, join: i64,
                  cap: i64, miter_limit: f32, tolerance: f32, out_pts: float2[>..<]&,
                  out_contours: Contour[>..<]&) {
    // Points on a circular arc about c of radius `half`, from direction d0
    // to d1 turning the short way, both ends left out.
    fn arc_points(c: float2, d0: float2, d1: float2) {
        let a0 = atan2(d0.y, d0.x);
        var sweep = atan2(cross2(d0, d1), dot(d0, d1));
        let step = 2.0 * acos(clamp(1.0 - tolerance / max(half, 0.0001), -1.0, 1.0));
        let n = clamp(ceil(abs(sweep) / max(step, 0.01)) as i64, 1, 256);
        for i in 1..n {
            let a = a0 + sweep * i / n;
            out_pts.push(c + float2 { cos(a) * half, sin(a) * half });
        }
    }
    // A join at p from direction a into direction b, on side s (+1 left,
    // -1 right of travel), between segments la and lb long: the outer side
    // gets the join; the inner side the point where the two sides' edges
    // meet, or, where that is past the end of either segment (a sharp turn,
    // short segments), a pivot through p, which the nonzero rule fills over.
    fn add_join(p: float2, a: float2, b: float2, s: f32, la: f32, lb: f32) {
        let na = perp(a) * float2 { s, s };
        let nb = perp(b) * float2 { s, s };
        let h = float2 { half, half };
        let p0 = p + na * h;
        let p1 = p + nb * h;
        let turn = cross2(a, b);
        // Turning toward the right (clockwise on the screen) makes the
        // left side the outer one.
        let outer = (turn > 0.0) == (s > 0.0);
        if abs(turn) < 0.00001 && dot(a, b) > 0.0 {
            out_pts.push(p0);
            return;
        }
        if !outer {
            let k = 1.0 + dot(na, nb);
            // How far back along each segment the sides meet.
            let back = half * abs(turn) / max(k, 0.000001);
            if k > 0.0001 && back <= min(la, lb) {
                out_pts.push(p + (na + nb) * float2 { half / k, half / k });
            } else {
                out_pts.push(p0);
                out_pts.push(p);
                out_pts.push(p1);
            }
            return;
        }
        out_pts.push(p0);
        if join == JOIN_ROUND {
            arc_points(p, na, nb);
        } else if join == JOIN_MITER {
            let k = 1.0 + dot(na, nb);
            // The miter's length over the half width is sqrt(2 / k).
            if k > 0.0001 && 2.0 / k <= miter_limit * miter_limit {
                out_pts.push(p + (na + nb) * float2 { half / k, half / k });
            }
        }
        out_pts.push(p1);
    }
    // A cap at p, the end of travel in direction d, from the left side to
    // the right; `kind` a CAP_*, or -1 for where pieces meet, a butt end.
    fn add_cap(p: float2, d: float2, kind: i64) {
        let n = perp(d);
        let h = float2 { half, half };
        if kind == 1 {              // CAP_ROUND
            out_pts.push(p + n * h);
            arc_points(p, n, d);
            out_pts.push(p + d * h);
            arc_points(p, d, n * float2 { -1, -1 });
            out_pts.push(p - n * h);
        } else if kind == 2 {       // CAP_SQUARE
            out_pts.push(p + n * h + d * h);
            out_pts.push(p - n * h + d * h);
        } else {
            out_pts.push(p + n * h);
            out_pts.push(p - n * h);
        }
    }
    fn start_outline() -> i64 { out_pts.len }
    var group = 0;
    // The outline from `first` on, a contour of its own group; its inner
    // edges skip_a_n from skip_a and skip_b_n from skip_b, counted from
    // first.
    fn finish(first: i64, skip_a: i64, skip_a_n: i64, skip_b: i64, skip_b_n: i64) {
        // The last point is often the first again.
        if out_pts.len - first >= 2 {
            let a = out_pts[first];
            let b = out_pts[out_pts.len - 1];
            if abs(a.x - b.x) < 0.00001 && abs(a.y - b.y) < 0.00001 { out_pts.resize(out_pts.len - 1); }
        }
        let count = out_pts.len - first;
        if count >= 3 {
            out_contours.push(Contour { first: first, count: count, closed: true,
                                        skip_a: skip_a, skip_a_n: if skip_a < count { skip_a_n } else { 0 },
                                        skip_b: skip_b, skip_b_n: if skip_b < count { skip_b_n } else { 0 },
                                        group: group });
            group++;
        } else {
            out_pts.resize(first);
        }
    }

    // An open stroke along piece_pts, with a cap of `start` and `end`
    // (CAP_*, or -1 for a butt end where the stroke goes on in another
    // piece, an edge inside the stroke): out along the left side, round the
    // end, back along the right, round the start.
    fn outline_piece(start: i64, end: i64) {
        let m = piece_pts.len;
        fn p(i: i64) -> float2 { piece_pts[i] }
        fn d(i: i64) -> float2 { unit(piece_pts[i + 1] - piece_pts[i]) }
        fn l(i: i64) -> f32 { length(piece_pts[i + 1] - piece_pts[i]) }
        let f = start_outline();
        let h = float2 { half, half };
        out_pts.push(p(0) + perp(d(0)) * h);
        for i in 1..m - 1 { add_join(p(i), d(i - 1), d(i), 1.0, l(i - 1), l(i)); }
        let end_edge = out_pts.len - f;
        add_cap(p(m - 1), d(m - 2), end);
        var i = m - 2;
        while i >= 1 {
            add_join(p(i), d(i) * float2 { -1, -1 }, d(i - 1) * float2 { -1, -1 }, 1.0, l(i), l(i - 1));
            i--;
        }
        let start_edge = out_pts.len - f;
        add_cap(p(0), d(0) * float2 { -1, -1 }, start);
        finish(f, end_edge, if end < 0 { 1 } else { 0 }, start_edge, if start < 0 { 1 } else { 0 });
    }

    for c in contours {
        let n = c.count;
        if n == 0 { continue; }
        if n == 1 || (n == 2 && c.closed && length(pts[c.first + 1] - pts[c.first]) < 0.00001) {
            // A dot: a round cap's circle, a square cap's square, else nothing.
            let p = pts[c.first];
            if cap == 0 { continue; }
            let f = start_outline();
            add_cap(p, float2 { 1, 0 }, cap);
            add_cap(p, float2 { -1, 0 }, cap);
            finish(f, 0, 0, 0, 0);
            continue;
        }
        fn at(i: i64) -> float2 { pts[c.first + (i % n + n) % n] }
        fn dir(i: i64) -> float2 { unit(at(i + 1) - at(i)) }   // the segment from point i
        fn len(i: i64) -> f32 { length(at(i + 1) - at(i)) }
        let looped = c.closed && n >= 3;
        let segs = if looped { n } else { n - 1 };
        if looped && segs <= STROKE_CHUNK {
            // Two loops: along the left side, and back along the right.
            var f = start_outline();
            for i in n { add_join(at(i), dir(i - 1), dir(i), 1.0, len(i - 1), len(i)); }
            finish(f, 0, 0, 0, 0);
            group--;        // the two loops are one outline
            f = start_outline();
            var i = n;
            while i > 0 {
                add_join(at(i), dir(i) * float2 { -1, -1 }, dir(i - 1) * float2 { -1, -1 }, 1.0,
                         len(i), len(i - 1));
                i--;
            }
            finish(f, 0, 0, 0, 0);
            continue;
        }
        // Pieces of about STROKE_CHUNK segments, cut across the middle of a
        // segment: a butt end both pieces share, point for point, so they
        // neither overlap nor leave a gap. An open line's first and last
        // pieces have its caps; a loop's pieces go round from the middle of
        // its first segment.
        fn mid(i: i64) -> float2 { (at(i) + at(i + 1)) * float2 { 0.5, 0.5 } }
        var from = if looped { 0 } else { -1 };     // the segment cut at the start; -1: point 0
        loop {
            // The segment cut at the end; an open line's last piece ends at
            // its last point instead, a loop's at the middle of its first
            // segment again (segment segs).
            var to = from + STROKE_CHUNK;
            let last = if looped { to >= segs } else { to >= segs - 1 };
            if last {
                to = segs;
            } else {
                // The longest segment in the second half of the piece: the
                // joins beside a cut must not reach across it, or the pieces
                // overlap there, which shows in a translucent stroke.
                var best = to;
                for k in from + STROKE_CHUNK / 2 + 1..to + 1 {
                    if len(k) > len(best) { best = k; }
                }
                to = best;
            }
            piece_pts.resize(0);
            piece_pts.push(if from < 0 { at(0) } else { mid(from) });
            for v in max(from + 1, 1)..to + 1 { piece_pts.push(at(v)); }
            if looped || !last { piece_pts.push(mid(to)); }
            outline_piece(if from < 0 { cap } else { -1 }, if last && !looped { cap } else { -1 });
            if last { break; }
            from = to;
        }
    }
}

// The contours cut into dashes by an on/off pattern starting `offset` into
// it, as open contours appended to out_pts and out_contours.
fn dash_contours(pts: const float2[:], contours: const Contour[:], pattern: const f32[:],
                 offset: f32, out_pts: float2[>..<]&, out_contours: Contour[>..<]&) {
    var total: f32 = 0.0;
    for d in pattern { total += max(d, 0.0); }
    if total <= 0.0 { return; }
    for c in contours {
        let segs = if c.closed { c.count } else { c.count - 1 };
        // Where in the pattern the contour starts.
        var k = 0;
        var left = pattern[0];
        var phase = offset % total;
        while phase > 0.0 {
            if phase >= left {
                phase -= left;
                k = (k + 1) % pattern.len;
                left = pattern[k];
            } else {
                left -= phase;
                phase = 0.0;
            }
        }
        var start = -1;
        if k % 2 == 0 {
            start = out_pts.len;
            out_pts.push(pts[c.first]);
        }
        for s in segs {
            let a = pts[c.first + s];
            let b = pts[c.first + (s + 1) % c.count];
            var len = length(b - a);
            var at: f32 = 0.0;
            while len > 0.0 {
                let step = min(left, len);
                at += step;
                len -= step;
                left -= step;
                let t = at / length(b - a);
                let q = a + (b - a) * float2 { t, t };
                if left <= 0.0 {
                    if k % 2 == 0 {
                        out_pts.push(q);
                        out_contours.push(Contour { first: start, count: out_pts.len - start,
                                                    closed: false });
                        start = -1;
                    } else {
                        start = out_pts.len;
                        out_pts.push(q);
                    }
                    k = (k + 1) % pattern.len;
                    left = pattern[k];
                } else if k % 2 == 0 && len <= 0.0 {
                    out_pts.push(q);
                }
            }
        }
        if start >= 0 {
            if out_pts.len - start >= 2 {
                out_contours.push(Contour { first: start, count: out_pts.len - start, closed: false });
            } else {
                out_pts.resize(start);
            }
        }
    }
}
