// gfx2d's paths without a GPU: building, flattening, and the triangles of
// fills and strokes, checked by area: the triangles' areas add up to the
// region the fill rule fills, exactly, whatever way it was cut up.
import std;
import vec;
import math;
import gfx2d from "../..";

// The area the tessellation covers, weighting each triangle by its
// vertices' mean alpha (1 inside, the fringe partly).
fn covered(v: const gfx2d::TessVertex[:], idx: const u32[:]) -> f64 {
    var sum = 0.0;
    var i = 0;
    while i + 2 < idx.len {
        let a = v[idx[i]];
        let b = v[idx[i + 1]];
        let c = v[idx[i + 2]];
        let area = abs(gfx2d::cross2(b.p - a.p, c.p - a.p)) * 0.5;
        sum += area * (a.alpha + b.alpha + c.alpha) / 3.0;
        i += 3;
    }
    sum
}

// The area a fill of p covers without a fringe, and with one a pixel wide.
fn fill_area(p: const gfx2d::Path&, rule: i64, fringe: f32) -> f64 {
    var pts: float2[>..<] = [];
    var contours: gfx2d::Contour[>..<] = [];
    gfx2d::flatten(p, gfx2d::IDENTITY, 0.01, pts, contours);
    var v: gfx2d::TessVertex[>..<] = [];
    var idx: u32[>..<] = [];
    gfx2d::fill_triangles(pts, contours, rule, fringe, v, idx);
    covered(v, idx)
}

fn stroke_area(p: const gfx2d::Path&, half: f32, join: i64, cap: i64, dash: const f32[:]) -> f64 {
    var pts: float2[>..<] = [];
    var contours: gfx2d::Contour[>..<] = [];
    gfx2d::flatten(p, gfx2d::IDENTITY, 0.01, pts, contours);
    var dpts: float2[>..<] = [];
    var dcontours: gfx2d::Contour[>..<] = [];
    if dash.len > 0 {
        gfx2d::dash_contours(pts, contours, dash, 0, dpts, dcontours);
    }
    var opts: float2[>..<] = [];
    var ocontours: gfx2d::Contour[>..<] = [];
    if dash.len > 0 {
        gfx2d::stroke_outline(dpts, dcontours, half, join, cap, 4, 0.01, opts, ocontours);
    } else {
        gfx2d::stroke_outline(pts, contours, half, join, cap, 4, 0.01, opts, ocontours);
    }
    var v: gfx2d::TessVertex[>..<] = [];
    var idx: u32[>..<] = [];
    gfx2d::fill_triangles(opts, ocontours, gfx2d::NONZERO, 0, v, idx);
    covered(v, idx)
}

// The same stroke drawn directly (stroke_triangles), with a fringe or not.
fn direct_area(p: const gfx2d::Path&, half: f32, join: i64, cap: i64, dash: const f32[:], fringe: f32) -> f64 {
    var pts: float2[>..<] = [];
    var contours: gfx2d::Contour[>..<] = [];
    gfx2d::flatten(p, gfx2d::IDENTITY, 0.01, pts, contours);
    var dpts: float2[>..<] = [];
    var dcontours: gfx2d::Contour[>..<] = [];
    if dash.len > 0 { gfx2d::dash_contours(pts, contours, dash, 0, dpts, dcontours); }
    var v: gfx2d::TessVertex[>..<] = [];
    var idx: u32[>..<] = [];
    if dash.len > 0 {
        gfx2d::stroke_triangles(dpts, dcontours, half, join, cap, 4, 0.01, fringe, v, idx);
    } else {
        gfx2d::stroke_triangles(pts, contours, half, join, cap, 4, 0.01, fringe, v, idx);
    }
    covered(v, idx)
}

fn check(name: const u8[:], got: f64, want: f64, tolerance: f64) {
    if abs(got - want) <= tolerance { print(name, ": ok"); }
    else { print(name, ": got ", got, ", want ", want); }
}

fn ring_path() -> gfx2d::Path {
    var ring = gfx2d::Path {};
    gfx2d::circle(ring, 0, 0, 100);
    return ring;
}

fn main() {
    var p = gfx2d::Path {};
    gfx2d::move_to(p, 10, 10);
    gfx2d::line_to(p, 20, 10);
    gfx2d::quad_to(p, 30, 10, 30, 20);
    gfx2d::cubic_to(p, 30, 30, 20, 40, 10, 30);
    gfx2d::close(p);
    print("elements: ", p.els.len, ", pen at ", gfx2d::current_point(p), ", bounds ", gfx2d::bounds(p));
    var pts: float2[>..<] = [];
    var contours: gfx2d::Contour[>..<] = [];
    gfx2d::flatten(p, gfx2d::IDENTITY, 0.25, pts, contours);
    print("flattened: ", contours.len, " contour, closed ", contours[0].closed, ", ",
          contours[0].count > 6 && contours[0].count < 40, " points");
    // Finer tolerance, more points.
    var fine: float2[>..<] = [];
    var fine_c: gfx2d::Contour[>..<] = [];
    gfx2d::flatten(p, gfx2d::scaling(10), 0.25, fine, fine_c);
    print("scaled up 10x: more points ", fine_c[0].count > contours[0].count);

    // Fills, without a fringe: exact areas.
    var sq = gfx2d::Path {};
    gfx2d::rect(sq, 0, 0, 100, 100);
    check("square", fill_area(sq, gfx2d::NONZERO, 0), 10000, 0.01);
    var circle = gfx2d::Path {};
    gfx2d::circle(circle, 50, 50, 40);
    check("circle", fill_area(circle, gfx2d::NONZERO, 0), PI * 1600, 0.5);
    // A hole wound the other way: out by either rule.
    var holed = gfx2d::Path {};
    gfx2d::rect(holed, 0, 0, 100, 100);
    gfx2d::move_to(holed, 25, 25);
    gfx2d::line_to(holed, 25, 75);
    gfx2d::line_to(holed, 75, 75);
    gfx2d::line_to(holed, 75, 25);
    gfx2d::close(holed);
    check("hole, nonzero", fill_area(holed, gfx2d::NONZERO, 0), 7500, 0.01);
    check("hole, even-odd", fill_area(holed, gfx2d::EVEN_ODD, 0), 7500, 0.01);
    // A hole wound the same way: filled by nonzero, out by even-odd.
    var same = gfx2d::Path {};
    gfx2d::rect(same, 0, 0, 100, 100);
    gfx2d::rect(same, 25, 25, 50, 50);
    check("same-way hole, nonzero", fill_area(same, gfx2d::NONZERO, 0), 10000, 0.01);
    check("same-way hole, even-odd", fill_area(same, gfx2d::EVEN_ODD, 0), 7500, 0.01);
    // A pentagram: nonzero fills its middle, even-odd does not.
    var star = gfx2d::Path {};
    let r = 50.0;
    for i in 5 {
        let a = -PI / 2 + i * 2 * TAU / 5;
        if i == 0 { gfx2d::move_to(star, r * cos(a), r * sin(a)); } else { gfx2d::line_to(star, r * cos(a), r * sin(a)); }
    }
    gfx2d::close(star);
    // The inner pentagon's circumradius is r * cos(72) / cos(36).
    let ri = r * cos(TAU / 5) / cos(PI / 5);
    let pentagon = 2.5 * ri * ri * sin(TAU / 5);
    let points = 2.5 * r * ri * sin(PI / 5) * 2 - pentagon;
    check("pentagram, nonzero", fill_area(star, gfx2d::NONZERO, 0), points + pentagon, 0.01);
    check("pentagram, even-odd", fill_area(star, gfx2d::EVEN_ODD, 0), points, 0.01);
    // A bow tie crosses itself in the middle.
    var bow = gfx2d::Path {};
    gfx2d::polygon(bow, [float2 { 0, 0 }, float2 { 100, 100 }, float2 { 100, 0 }, float2 { 0, 100 }]);
    check("bow tie", fill_area(bow, gfx2d::NONZERO, 0), 5000, 0.01);
    var starred = gfx2d::Path {};
    gfx2d::star(starred, 0, 0, 5, 50, 20);
    check("star()", fill_area(starred, gfx2d::NONZERO, 0), 5 * 50 * 20 * sin(PI / 5), 0.01);
    var hexagon = gfx2d::Path {};
    gfx2d::regular_polygon(hexagon, 0, 0, 10, 6);
    check("hexagon", fill_area(hexagon, gfx2d::NONZERO, 0), 1.5 * sqrt(3.0) * 100, 0.01);
    var rr = gfx2d::Path {};
    gfx2d::rounded_rect(rr, 0, 0, 100, 60, 10);
    check("rounded rect", fill_area(rr, gfx2d::NONZERO, 0), 6000 - (4 - PI) * 100, 0.5);

    // The fringe adds about half a pixel's worth along the outline; a
    // convex fill's, none.
    check("convex fringe", fill_area(sq, gfx2d::NONZERO, 1), 10000, 0.5);
    check("general fringe", fill_area(holed, gfx2d::NONZERO, 1), 7500 + 0.125 * 600, 1);

    // The fringe goes outward: its outer edge lies outside the fill.
    fn fringe_outside(p: const gfx2d::Path&, rule: i64) -> bool {
        var pts: float2[>..<] = [];
        var contours: gfx2d::Contour[>..<] = [];
        gfx2d::flatten(p, gfx2d::IDENTITY, 0.01, pts, contours);
        var v: gfx2d::TessVertex[>..<] = [];
        var idx: u32[>..<] = [];
        gfx2d::fill_triangles(pts, contours, rule, 1, v, idx);
        for q in v {
            if q.alpha == 0.0 && gfx2d::filled(gfx2d::winding_at(pts, contours, q.p), rule) { return false; }
        }
        true
    }
    print("fringe outward: convex ", fringe_outside(sq, gfx2d::NONZERO), ", holed ",
          fringe_outside(holed, gfx2d::NONZERO), ", even-odd ", fringe_outside(same, gfx2d::EVEN_ODD),
          ", star ", fringe_outside(starred, gfx2d::NONZERO));

    print("contains: ", gfx2d::contains(holed, float2 { 10, 10 }), " ",
          gfx2d::contains(holed, float2 { 50, 50 }), " ",
          gfx2d::contains(same, float2 { 50, 50 }), " ",
          gfx2d::contains(same, float2 { 50, 50 }, gfx2d::EVEN_ODD));

    // Strokes.
    var seg = gfx2d::Path {};
    gfx2d::move_to(seg, 0, 0);
    gfx2d::line_to(seg, 100, 0);
    check("butt", stroke_area(seg, 5, gfx2d::JOIN_MITER, 0, []), 1000, 0.01);
    check("square cap", stroke_area(seg, 5, gfx2d::JOIN_MITER, 2, []), 1100, 0.01);
    check("round cap", stroke_area(seg, 5, gfx2d::JOIN_MITER, 1, []), 1000 + PI * 25, 0.5);
    var corner = gfx2d::Path {};
    gfx2d::move_to(corner, 0, 0);
    gfx2d::line_to(corner, 100, 0);
    gfx2d::line_to(corner, 100, 100);
    check("miter join", stroke_area(corner, 5, gfx2d::JOIN_MITER, 0, []), 2000, 0.01);
    check("bevel join", stroke_area(corner, 5, gfx2d::JOIN_BEVEL, 0, []), 2000 - 12.5, 0.01);
    check("round join", stroke_area(corner, 5, gfx2d::JOIN_ROUND, 0, []), 2000 - 25 + PI * 25 / 4, 0.05);
    // The other way round the corner: the joins are on the other side.
    var left = gfx2d::Path {};
    gfx2d::move_to(left, 0, 0);
    gfx2d::line_to(left, 100, 0);
    gfx2d::line_to(left, 100, -100);
    check("left turn", stroke_area(left, 5, gfx2d::JOIN_MITER, 0, []), 2000, 0.01);
    // A closed square's stroke: a frame 10 wide.
    check("closed", stroke_area(sq, 5, gfx2d::JOIN_MITER, 0, []), 110 * 110 - 90 * 90, 0.01);
    // A stroke crossing itself is drawn once where it does: with round
    // joins and caps, it is every point within half its width of the
    // line, which sampling finds.
    let line_pts = [float2 { 0, 50 }, float2 { 100, 50 }, float2 { 50, 0 }, float2 { 50, 100 }];
    var cross = gfx2d::Path {};
    gfx2d::polygon(cross, line_pts, false);
    var hits = 0;
    for yi in -60..1060 {
        for xi in -60..1060 {
            let q = float2 { xi * 0.1 + 0.05, yi * 0.1 + 0.05 };
            var near = false;
            for i in 3 {
                let a = line_pts[i];
                let d = line_pts[i + 1] - a;
                let t = clamp(dot(q - a, d) / dot(d, d), 0.0, 1.0);
                if length(q - (a + d * float2 { t, t })) <= 5.0 { near = true; }
            }
            if near { hits++; }
        }
    }
    check("self-crossing", stroke_area(cross, 5, gfx2d::JOIN_ROUND, 1, []), hits * 0.01, 3);
    // Dashes: 10 on, 10 off along 100: five dashes of 10 by 10.
    check("dashes", stroke_area(seg, 5, gfx2d::JOIN_MITER, 0, [10.0, 10.0]), 500, 0.01);
    check("dashes, round caps", stroke_area(seg, 5, gfx2d::JOIN_MITER, 1, [10.0, 10.0]),
          500 + 5 * PI * 25, 2);
    // A dot is a round cap's circle.
    var dot = gfx2d::Path {};
    gfx2d::move_to(dot, 5, 5);
    gfx2d::line_to(dot, 5, 5);
    check("dot", stroke_area(dot, 5, gfx2d::JOIN_MITER, 1, []), PI * 25, 0.5);

    // The direct stroke covers the same, with its joins' outer corners as
    // fans and kites and its body as a strip, and its fringe adds nothing
    // to the area (the ramp from covered to not is exact along an edge; a
    // flat cap's corners are within a third of a pixel); only where it
    // overlaps itself is there more.
    check("direct butt", direct_area(seg, 5, gfx2d::JOIN_MITER, 0, [], 0), 1000, 0.01);
    check("direct butt, fringed", direct_area(seg, 5, gfx2d::JOIN_MITER, 0, [], 1), 1000, 0.5);
    check("direct square cap", direct_area(seg, 5, gfx2d::JOIN_MITER, 2, [], 1), 1100, 0.5);
    check("direct round cap", direct_area(seg, 5, gfx2d::JOIN_MITER, 1, [], 1), 1000 + PI * 25, 0.5);
    check("direct miter join", direct_area(corner, 5, gfx2d::JOIN_MITER, 0, [], 1), 2000, 0.5);
    check("direct bevel join", direct_area(corner, 5, gfx2d::JOIN_BEVEL, 0, [], 1), 2000 - 12.5, 0.5);
    check("direct round join", direct_area(corner, 5, gfx2d::JOIN_ROUND, 0, [], 1), 2000 - 25 + PI * 25 / 4, 0.5);
    check("direct left turn", direct_area(left, 5, gfx2d::JOIN_MITER, 0, [], 1), 2000, 0.5);
    check("direct closed", direct_area(sq, 5, gfx2d::JOIN_MITER, 0, [], 1), 110 * 110 - 90 * 90, 0.1);
    check("direct closed, round", direct_area(sq, 5, gfx2d::JOIN_ROUND, 0, [], 1),
          110 * 110 - 90 * 90 - (4 - PI) * 25, 0.5);
    check("direct dashes", direct_area(seg, 5, gfx2d::JOIN_MITER, 0, [10.0, 10.0], 1), 500, 2);
    check("direct dashes, round caps", direct_area(seg, 5, gfx2d::JOIN_MITER, 1, [10.0, 10.0], 1),
          500 + 5 * PI * 25, 2);
    check("direct dot", direct_area(dot, 5, gfx2d::JOIN_MITER, 1, [], 1), PI * 25, 0.5);
    check("direct square dot", direct_area(dot, 5, gfx2d::JOIN_MITER, 2, [], 1), 100, 2);
    let ring = ring_path();
    check("direct ring", direct_area(ring, 5, gfx2d::JOIN_ROUND, 0, [], 1), PI * (105 * 105 - 95 * 95), 1);
    // Crossing itself, it is drawn twice there: a square of the width more.
    check("direct self-crossing", direct_area(cross, 5, gfx2d::JOIN_ROUND, 1, [], 0), hits * 0.01 + 100, 3);
    // Segments shorter than the width, turning sharply: the inner sides
    // pivot and overlap, so there is more than the union, never less.
    var zag = gfx2d::Path {};
    gfx2d::polygon(zag, [float2 { 0, 0 }, float2 { 3, 0 }, float2 { 0, 3 }, float2 { 3, 6 }, float2 { 0, 9 }], false);
    print("direct sharp zigzag: at least the union ",
          direct_area(zag, 5, gfx2d::JOIN_MITER, 0, [], 1) >= stroke_area(zag, 5, gfx2d::JOIN_MITER, 0, []) - 0.01);

    // Meshes: a path tessellated once, the same each time, covering what
    // its fill or stroke does.
    let mesh = gfx2d::tessellate(starred, gfx2d::NONZERO, 1.0);
    let again = gfx2d::tessellate(starred, gfx2d::NONZERO, 1.0);
    print("mesh: ", mesh.indices.len / 3, " triangles, the same again ",
          mesh.indices == again.indices && mesh.vertices.len == again.vertices.len, ", the fill's area ",
          abs(covered(mesh.vertices, mesh.indices) - fill_area(starred, gfx2d::NONZERO, 1)) < 0.01);
    let stroked = gfx2d::tessellate_stroke(corner, gfx2d::Stroke { width: 10 }, 1.0);
    check("mesh stroke", covered(stroked.vertices, stroked.indices), 2000, 0.5);
    // Made for twice the scale, the fringe is half as wide in the path's
    // units, and the area the same; a hairline's alpha is its width.
    let fine = gfx2d::tessellate_stroke(corner, gfx2d::Stroke { width: 10 }, 2.0);
    let hair = gfx2d::tessellate_stroke(corner, gfx2d::Stroke { width: 0.25 }, 1.0);
    let once = gfx2d::tessellate_stroke(cross, gfx2d::Stroke { width: 10, join: gfx2d::JOIN_ROUND as i32, cap: 1 }, 1.0, true, false);
    print("mesh at scale 2: ", abs(covered(fine.vertices, fine.indices) - 2000) < 0.5, ", scale ", fine.scale,
          "; a hairline's alpha ", hair.alpha, "; drawn once where it crosses ",
          abs(covered(once.vertices, once.indices) - hits * 0.01) < 3);

    // A long stroke is outlined in pieces, each tessellated alone, cut across
    // the middle of segments so that together they cover the stroke exactly
    // once.
    fn pieces_and_union(p: const gfx2d::Path&, half: f32, join: i64) -> i64, f64, f64 {
        var zpts: float2[>..<] = [];
        var zcs: gfx2d::Contour[>..<] = [];
        gfx2d::flatten(p, gfx2d::IDENTITY, 0.01, zpts, zcs);
        var opts: float2[>..<] = [];
        var ocs: gfx2d::Contour[>..<] = [];
        gfx2d::stroke_outline(zpts, zcs, half, join, 0, 4, 0.01, opts, ocs);
        var pieces = 0.0;
        var groups = 0;
        var a = 0;
        while a < ocs.len {
            var b = a + 1;
            while b < ocs.len && ocs[b].group == ocs[a].group { b++; }
            var v: gfx2d::TessVertex[>..<] = [];
            var idx: u32[>..<] = [];
            gfx2d::fill_triangles(opts, ocs[a..b], gfx2d::NONZERO, 0, v, idx);
            pieces += covered(v, idx);
            groups++;
            a = b;
        }
        var all_v: gfx2d::TessVertex[>..<] = [];
        var all_idx: u32[>..<] = [];
        gfx2d::fill_triangles(opts, ocs, gfx2d::NONZERO, 0, all_v, all_idx);
        return groups, pieces, covered(all_v, all_idx);
    }
    var zig = gfx2d::Path {};
    for i in 101 {
        let y = if i % 2 == 0 { 0.0 } else { 20.0 };
        if i == 0 { gfx2d::move_to(zig, 0, y); } else { gfx2d::line_to(zig, i * 10, y); }
    }
    let groups, pieces, union = pieces_and_union(zig, 2, gfx2d::JOIN_MITER);
    print("zigzag in pieces: ", groups, " groups; no overlap ", abs(pieces - union) < 0.01,
          ", union ", abs(union - 100 * sqrt(500.0) * 4) < 40);
    var wave = gfx2d::Path {};
    for i in 101 {
        let y = 20 * sin(i * 0.3);
        if i == 0 { gfx2d::move_to(wave, 0, y); } else { gfx2d::line_to(wave, i * 10, y); }
    }
    let wgroups, wpieces, wunion = pieces_and_union(wave, 3, gfx2d::JOIN_MITER);
    print("wave in pieces: ", wgroups, " groups; no overlap ", abs(wpieces - wunion) < 0.01);
    let rgroups, rpieces, runion = pieces_and_union(ring, 5, gfx2d::JOIN_ROUND);
    print("circle in pieces: ", rgroups > 2, " groups; no overlap ", abs(rpieces - runion) < 0.01,
          ", the ring's area ", abs(runion - PI * (105 * 105 - 95 * 95)) < 1);

    // transform() moves every point.
    var moved = gfx2d::Path {};
    gfx2d::rect(moved, 0, 0, 10, 10);
    gfx2d::transform(moved, gfx2d::mul(gfx2d::translation(5, 5), gfx2d::scaling(2)));
    print("transformed: ", gfx2d::bounds(moved));

    // SVG path data.
    var svg = gfx2d::Path {};
    print("svg rect: ", gfx2d::svg_path(svg, "M10,10 H110 V60 h-100 z"), " area ",
          fill_area(svg, gfx2d::NONZERO, 0));
    var rel = gfx2d::Path {};
    print("svg compact relative: ", gfx2d::svg_path(rel, "m10 10l100 0 0 50-100 0z"), " area ",
          fill_area(rel, gfx2d::NONZERO, 0));
    var curves = gfx2d::Path {};
    let curves_ok = gfx2d::svg_path(curves, "M0 50C0-17 100-17 100 50S0 117 0 50zM20 50Q50 0 80 50T20 50z");
    print("svg curves: ", curves_ok, ", ", curves.els.len, " elements, pen at ",
          gfx2d::current_point(curves), ", bounds ", gfx2d::bounds(curves));
    var nums = gfx2d::Path {};
    print("svg numbers: ", gfx2d::svg_path(nums, "M.5.5L1e1-2.5e0"), " ", nums.els[1]);
    var arc = gfx2d::Path {};
    var junk = gfx2d::Path {};
    print("svg arc: ", gfx2d::svg_path(arc, "M0 0A10 10 0 0 1 20 0"), ", junk: ", gfx2d::svg_path(junk, "M0 0 L x"),
          ", leading number: ", gfx2d::svg_path(junk, "10 10"));
    // warp moves every point.
    var w = gfx2d::Path {};
    gfx2d::rect(w, 0, 0, 10, 10);
    gfx2d::warp(w) { q => q + float2 { q.y, 0 } };
    print("warped: ", gfx2d::bounds(w), " area ", fill_area(w, gfx2d::NONZERO, 0));

    // Many contours in one path: a grid of diamonds, some with a hole, and
    // slanted stripes, with the fringe (whose side test asks only the
    // contours around a point) and without.
    var grid = gfx2d::Path {};
    for j in 10 {
        for i in 10 {
            let x = 20.0 + i * 30;
            let y = 20.0 + j * 30;
            gfx2d::move_to(grid, x, y - 10);
            gfx2d::line_to(grid, x + 10, y);
            gfx2d::line_to(grid, x, y + 10);
            gfx2d::line_to(grid, x - 10, y);
            gfx2d::close(grid);
            if (i + j) % 3 == 0 {
                // A hole, wound the other way.
                gfx2d::move_to(grid, x - 2, y - 2);
                gfx2d::line_to(grid, x - 2, y + 2);
                gfx2d::line_to(grid, x + 2, y + 2);
                gfx2d::line_to(grid, x + 2, y - 2);
                gfx2d::close(grid);
            }
        }
    }
    let holes = 34.0;
    let grid_area = 100 * 200 - holes * 16;
    // A fringe adds an eighth of a pixel per unit of edge, outward from
    // the fill on both kinds of contour.
    let grid_edges = 100 * 4 * sqrt(200.0) + holes * 16;
    check("diamond grid", fill_area(grid, gfx2d::NONZERO, 0), grid_area, 0.5);
    check("diamond grid, even-odd", fill_area(grid, gfx2d::EVEN_ODD, 0), grid_area, 0.5);
    check("diamond grid, fringe", fill_area(grid, gfx2d::NONZERO, 1) - grid_area, grid_edges * 0.125, grid_edges * 0.03);
    check("diamond grid, even-odd fringe", fill_area(grid, gfx2d::EVEN_ODD, 1) - grid_area, grid_edges * 0.125,
          grid_edges * 0.03);
    var bars = gfx2d::Path {};
    for i in 50 {
        let x = i * 6.0;
        gfx2d::move_to(bars, x, 0);
        gfx2d::line_to(bars, x + 2, 0);
        gfx2d::line_to(bars, x + 52, 100);
        gfx2d::line_to(bars, x + 50, 100);
        gfx2d::close(bars);
    }
    let bar_edges = 50 * (4 + 2 * sqrt(50.0 * 50 + 100 * 100));
    check("stripes", fill_area(bars, gfx2d::NONZERO, 0), 50 * 200, 0.5);
    check("stripes, fringe", fill_area(bars, gfx2d::NONZERO, 1) - 50 * 200, bar_edges * 0.125, bar_edges * 0.03);
}
