// gfx2d's paths drawn headless and read back: fills under both rules,
// strokes of each join and cap, dashes, hairlines, polygons and polylines,
// checked by the coverage they leave; a translucent stroke crossing itself
// drawn once there; paints on paths; and draw order across shapes and paths.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../..";

let W = 128;

var target: gfx::Texture;
var px: u8[>..] = [];

fn area<F>() -> f64 {
    gfx2d::draw_into(target, gfx2d::BLACK) { F(); };
    px = gfx::read_pixels(target);
    var sum = 0.0;
    for i in W * W { sum += px[i * 4] / 255.0; }
    sum
}

fn check_area(name: const u8[:], got: f64, want: f64, tolerance: f64) {
    if abs(got - want) <= tolerance { print(name, ": ok"); }
    else { print(name, ": got ", got, ", want ", want); }
}

fn at(x: i64, y: i64) -> u8[>..] {
    let i = (y * W + x) * 4;
    str(px[i], ",", px[i + 1], ",", px[i + 2], ",", px[i + 3])
}

fn main() {
    guard gfx::open_headless(W, W) else {
        print("gfx: ", gfx::error());
        return;
    }
    target = gfx::render_target(W, W, gfx::RGBA8);
    let white = gfx2d::WHITE;

    // Fills. The tolerance allows about a tenth of a pixel per pixel of
    // outline, as for the shapes.
    var sq = gfx2d::Path {};
    gfx2d::rect(sq, 20.5, 20.5, 60, 40);
    check_area("square", area() { gfx2d::fill(sq, white); }, 2400, 5);
    var circle = gfx2d::Path {};
    gfx2d::circle(circle, 64, 64, 40);
    check_area("circle", area() { gfx2d::fill(circle, white); }, PI * 1600, 25);
    var holed = gfx2d::Path {};
    gfx2d::rect(holed, 10, 10, 100, 100);
    gfx2d::rect(holed, 35, 35, 50, 50);
    check_area("nonzero", area() { gfx2d::fill(holed, white); }, 10000, 10);
    check_area("even-odd", area() { gfx2d::fill(holed, white, gfx2d::EVEN_ODD); }, 7500, 30);
    // A fill that is not convex has a fringe half a pixel wide outside it,
    // which adds about an eighth of a pixel per pixel of outline: 350 here.
    check_area("star", area() { gfx2d::star(64, 64, 5, 50, 20, white); }, 5 * 50 * 20 * sin(PI / 5) + 44, 15);
    check_area("rotated, scaled", area() {
        gfx2d::translate(64, 64) { gfx2d::rotate(0.5) { gfx2d::scale(2) {
            gfx2d::polygon([float2 { -15, -10 }, float2 { 15, -10 }, float2 { 15, 10 }, float2 { -15, 10 }], white);
        }; }; };
    }, 2400, 10);
    check_area("triangle", area() { gfx2d::triangle(10, 10, 110, 10, 10, 90, white); }, 4000, 15);

    // Strokes.
    var seg = gfx2d::Path {};
    gfx2d::move_to(seg, 14, 64);
    gfx2d::line_to(seg, 114, 64);
    check_area("stroke", area() { gfx2d::stroke(seg, 6, white); }, 600, 15);
    check_area("round caps", area() {
        gfx2d::stroke(seg, gfx2d::Stroke { width: 6, cap: gfx2d::CAP_ROUND }, white);
    }, 600 + PI * 9, 15);
    check_area("hairline", area() { gfx2d::stroke(seg, 0.5, white); }, 50, 5);
    check_area("dashed", area() {
        gfx2d::stroke(seg, gfx2d::Stroke { width: 6, dash: [10, 10] }, white);
    }, 300, 15);
    check_area("polyline", area() {
        gfx2d::polyline([float2 { 20, 20 }, float2 { 100, 20 }, float2 { 100, 100 }], 4, white);
    }, 640, 15);
    check_area("polygon outline", area() {
        gfx2d::polygon_outline([float2 { 20, 20 }, float2 { 100, 20 }, float2 { 100, 100 }, float2 { 20, 100 }],
                               4, white);
    }, 84 * 84 - 76 * 76, 20);
    // A stroke scaled 2x is twice as wide; one in pixels is not.
    let scaled = area() { gfx2d::translate(-14, 0) { gfx2d::scale(1, 2) { gfx2d::translate(14, -32) {
        gfx2d::stroke(seg, 3, white);
    }; }; }; };
    let in_pixels = area() { gfx2d::scale(1, 2) { gfx2d::translate(0, -32) {
        gfx2d::stroke(seg, gfx2d::Stroke { width: 3, pixels: true }, white);
    }; }; };
    check_area("stretched stroke", scaled, 600, 15);
    check_area("stroke in pixels", in_pixels, 300, 15);

    // A translucent stroke crossing itself, and with sharp joins, is drawn
    // once everywhere: where it crosses is no brighter than elsewhere.
    gfx2d::draw_into(target, gfx2d::BLACK) {
        gfx2d::polyline([float2 { 10, 64 }, float2 { 118, 64 }, float2 { 64, 10 }, float2 { 64, 118 }], 8,
                        gfx2d::rgba(0xFFFFFF, 0.5));
    };
    px = gfx::read_pixels(target);
    print("crossing: ", at(64, 64), " elsewhere ", at(30, 64), " ", at(64, 100), " at the join ", at(112, 64));

    // Paints on paths.
    gfx2d::draw_into(target, gfx2d::BLACK) {
        gfx2d::fill(holed, gfx2d::linear(10, 0, 110, 0, gfx2d::BLACK, gfx2d::WHITE), gfx2d::EVEN_ODD);
    };
    px = gfx::read_pixels(target);
    print("gradient fill: ", px[(20 * W + 15) * 4] < 20, " ", px[(20 * W + 105) * 4] > 235, " hole ", at(60, 60));

    // A mesh made once draws as the path does, under the transform it is
    // drawn under.
    let mesh = gfx2d::tessellate(holed, gfx2d::EVEN_ODD);
    gfx2d::draw_into(target, gfx2d::BLACK) {
        gfx2d::translate(3, 2) { gfx2d::fill(holed, white, gfx2d::EVEN_ODD); };
    };
    px = gfx::read_pixels(target);
    let by_fill = copy(px);
    gfx2d::draw_into(target, gfx2d::BLACK) { gfx2d::translate(3, 2) { gfx2d::draw(mesh, white); }; };
    px = gfx::read_pixels(target);
    print("mesh: the fill's pixels ", px == by_fill, ", ", gfx2d::stats().triangles, " triangles");

    // Shapes and paths keep the order they were drawn in.
    gfx2d::draw_into(target, gfx2d::BLACK) {
        gfx2d::rect(0, 0, 20, 20, gfx2d::RED);
        gfx2d::polygon([float2 { 5, 5 }, float2 { 15, 5 }, float2 { 15, 15 }, float2 { 5, 15 }], gfx2d::LIME);
        gfx2d::circle(10, 10, 2, gfx2d::BLUE);
    };
    px = gfx::read_pixels(target);
    let s = gfx2d::stats();
    print("order: ", at(2, 2), " ", at(7, 7), " ", at(10, 10), "; ", s.instances, " instances, ",
          s.triangles > 0, " triangles, ", s.draws, " draws");
    gfx::close();
}
