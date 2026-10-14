// gfx2d's shapes drawn headless into a texture and read back. A shape on
// pixel boundaries comes out exact; an antialiased one is checked by its
// area: the coverage of every pixel added up is the shape's area, within
// a fraction of a pixel per unit of edge, on any backend.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../..";

let W = 128;

var target: gfx::Texture;

// The coverage of white drawn on black, summed over the target, in pixels.
fn area<F>() -> f64 {
    gfx2d::draw_into(target, gfx2d::BLACK) { F(); };
    let px = gfx::read_pixels(target);
    var sum = 0.0;
    for i in W * W { sum += px[i * 4] / 255.0; }
    sum
}

fn check_area(name: const u8[:], got: f64, want: f64, tolerance: f64) {
    let ok = abs(got - want) <= tolerance;
    if ok { print(name, ": ok"); } else { print(name, ": got ", got, ", want ", want); }
}

fn pixel(px: u8[:], x: i64, y: i64) -> u8[>..] {
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

    // On pixel boundaries: exact, with no partly covered pixels.
    gfx2d::draw_into(target, gfx2d::BLACK) { gfx2d::rect(10, 20, 30, 15, white); };
    var px = gfx::read_pixels(target);
    var full = 0;
    var partial = 0;
    for i in W * W {
        if px[i * 4] == 255 { full++; } else if px[i * 4] != 0 { partial++; }
    }
    print("aligned rect: ", full, " full, ", partial, " partial; corners ", pixel(px, 10, 20), " ",
          pixel(px, 39, 34), " outside ", pixel(px, 9, 20), " ", pixel(px, 40, 35));

    // Colors arrive as given.
    gfx2d::draw_into(target, gfx2d::BLACK) { gfx2d::rect(0, 0, 8, 8, gfx2d::rgb(0x336699)); };
    px = gfx::read_pixels(target);
    print("color: ", pixel(px, 4, 4));
    gfx2d::draw_into(target, gfx2d::BLUE) { gfx2d::rect(0, 0, 8, 8, gfx2d::rgba(0xFF0000, 0.5)); };
    px = gfx::read_pixels(target);
    let r: i64 = px[(4 * W + 4) * 4];
    let b: i64 = px[(4 * W + 4) * 4 + 2];
    print("half red over blue: ", abs(r - 128) <= 1 && abs(b - 128) <= 1 && px[(4 * W + 4) * 4 + 1] == 0);

    // Areas. The tolerance is about a tenth of a pixel per pixel of edge.
    let pi = PI;
    check_area("circle", area() { gfx2d::circle(64, 64, 40, white); }, pi * 1600, 8);
    check_area("off-grid circle", area() { gfx2d::circle(40.3, 50.7, 12.5, white); },
               pi * 12.5 * 12.5, 3);
    check_area("ellipse", area() { gfx2d::ellipse(64, 64, 50, 20, white); }, pi * 1000, 8);
    check_area("rounded rect", area() { gfx2d::rounded_rect(20, 30, 80, 50, 12, white); },
               80 * 50 - (4 - pi) * 144, 8);
    check_area("corner radii", area() {
        gfx2d::rounded_rect(20, 30, 80, 50, float4 { 0, 10, 20, 0 }, white);
    }, 80 * 50 - (4 - pi) * 0.25 * (100 + 400), 8);
    check_area("rect outline", area() { gfx2d::rect_outline(20, 20, 60, 40, 4, white); },
               2 * 4 * (60 + 40), 8);
    check_area("ring", area() { gfx2d::ring(64, 64, 20, 30, white); }, pi * (900 - 400), 8);
    check_area("circle outline, hairline", area() {
        gfx2d::circle_outline(64, 64, 30, 0.25, white);
    }, 2 * pi * 30 * 0.25, 4);
    check_area("quarter pie", area() { gfx2d::pie(30, 30, 60, 0, pi / 2, white); },
               pi * 3600 / 4, 8);
    check_area("three-quarter pie", area() { gfx2d::pie(64, 64, 40, 0, 1.5 * pi, white); },
               pi * 1600 * 0.75, 8);
    check_area("full pie", area() { gfx2d::pie(64, 64, 40, -1, TAU - 1, white); }, pi * 1600, 8);
    check_area("whole arc", area() { gfx2d::arc(64, 64, 40, 0, 7, 6, white); }, TAU * 40 * 6, 8);
    check_area("arc", area() { gfx2d::arc(64, 64, 40, pi, TAU, 6, white); }, pi * 40 * 6, 8);
    check_area("round-capped arc", area() {
        gfx2d::arc(64, 64, 40, pi, TAU, 6, white, gfx2d::CAP_ROUND);
    }, pi * 40 * 6 + pi * 9, 8);
    check_area("line", area() { gfx2d::line(20, 20, 60, 50, 4, white); }, 200, 4);
    check_area("round-capped line", area() {
        gfx2d::line(20, 20, 60, 50, 4, white, gfx2d::CAP_ROUND);
    }, 200 + pi * 4, 4);
    check_area("square-capped line", area() {
        gfx2d::line(20, 20, 60, 50, 4, white, gfx2d::CAP_SQUARE);
    }, 216, 4);

    // Under transforms, areas scale by the determinant and edges stay sharp.
    check_area("rotated rect", area() {
        gfx2d::translate(64, 64) { gfx2d::rotate(0.3) { gfx2d::rect(-30, -15, 60, 30, white); }; };
    }, 1800, 8);
    check_area("scaled circle", area() {
        gfx2d::scale(2) { gfx2d::circle(32, 32, 20, white); };
    }, pi * 1600, 8);
    check_area("squashed circle", area() {
        gfx2d::translate(64, 64) { gfx2d::scale(2, 0.5) { gfx2d::circle(0, 0, 30, white); }; };
    }, pi * 900, 8);
    check_area("skewed rect", area() {
        gfx2d::translate(64, 64) { gfx2d::skew(0.4, 0) { gfx2d::rect(-20, -20, 40, 40, white); }; };
    }, 1600, 8);

    // A block restores the transform; push and pop do too.
    var after = gfx2d::IDENTITY;
    var popped = gfx2d::IDENTITY;
    gfx2d::draw_into(target, gfx2d::BLACK) {
        gfx2d::translate(5, 6) { gfx2d::rotate(1) { gfx2d::circle(0, 0, 1, white); }; };
        after = gfx2d::current_transform();
        gfx2d::push();
        gfx2d::scale(3);
        gfx2d::pop();
        popped = gfx2d::current_transform();
    };
    print("transform restored: ", after == gfx2d::IDENTITY, " ", popped == gfx2d::IDENTITY);
    let local = block {
        var p = float2_0;
        gfx2d::draw_into(target, gfx2d::BLACK) {
            gfx2d::translate(10, 20);
            gfx2d::scale(2);
            p = gfx2d::to_local(float2 { 30, 40 });
        };
        p
    };
    print("to_local: ", local);

    // Many shapes, one draw.
    gfx2d::draw_into(target, gfx2d::BLACK) {
        for i in 1000 { gfx2d::circle((i % 32) * 4, (i / 32) * 4, 1.5, white); }
        gfx2d::rect(0, 0, 4, 4, white);
    };
    let s = gfx2d::stats();
    print("stats: ", s.instances, " instances, ", s.draws, " draw");

    // The screen works as a target too.
    gfx2d::frame(gfx2d::rgb(0x102030)) { gfx2d::rect(0, 0, 4, 4, gfx2d::RED); };
    px = gfx::read_pixels(gfx::screen());
    print("screen: ", pixel(px, 1, 1), " ", pixel(px, 8, 8));
    gfx::close();
}
