// gfx2d's clips and layers drawn headless and read back: clips of each
// shape, nested, rotated, by a path, under meshes and text; layers' group
// opacity, blend modes, blur and shadows; box_shadow; and multisampling.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../..";

let W = 128;

var target: gfx::Texture;
var px: u8[>..] = [];

fn draw<F>(clear: gfx2d::Color) {
    gfx2d::draw_into(target, clear) { F(); };
    px = gfx::read_pixels(target);
}
fn area<F>() -> f64 {
    draw(gfx2d::BLACK) { F(); };
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
fn near(x: i64, y: i64, r: i64, g: i64, b: i64, a: i64) -> bool {
    let i = (y * W + x) * 4;
    abs(px[i] - r) <= 2 && abs(px[i + 1] - g) <= 2 && abs(px[i + 2] - b) <= 2 && abs(px[i + 3] - a) <= 2
}

fn main() {
    guard gfx::open_headless(W, W) else {
        print("gfx: ", gfx::error());
        return;
    }
    target = gfx::render_target(W, W, gfx::RGBA8);
    let white = gfx2d::WHITE;
    fn everything() { gfx2d::rect(0, 0, W, W, white); }

    // Clips: what is drawn inside them, by area.
    check_area("clip_rect", area() { gfx2d::clip_rect(20, 20, 40, 30) { everything(); }; }, 1200, 0.5);
    check_area("clip_rect, fractional", area() { gfx2d::clip_rect(20.25, 20.5, 40.5, 30.25) { everything(); }; },
               40.5 * 30.25, 1.5);
    check_area("clip_rect, turned", area() {
        gfx2d::translate(64, 64) { gfx2d::rotate(0.6) {
            gfx2d::clip_rect(-20, -15, 40, 30) { gfx2d::rect(-100, -100, 200, 200, white); };
        }; };
    }, 1200, 3);
    check_area("clip_circle", area() { gfx2d::clip_circle(64, 64, 40) { everything(); }; }, PI * 1600, 3);
    check_area("clip_rounded_rect", area() { gfx2d::clip_rounded_rect(14, 24, 100, 80, 20) { everything(); }; },
               8000 - (4 - PI) * 400, 3);
    check_area("nested", area() {
        gfx2d::clip_circle(64, 64, 40) { gfx2d::clip_rect(64, 0, 64, 128) { everything(); }; };
    }, PI * 800, 3);
    var star = gfx2d::Path {};
    gfx2d::star(star, 64, 64, 50, 20, 5);
    let star_area = 5 * 50 * 20 * sin(PI / 5);
    check_area("clip_path", area() { gfx2d::clip_path(star) { everything(); }; }, star_area, 50);
    check_area("clip_path in a clip", area() {
        gfx2d::clip_rect(0, 0, 64, 128) {
            var c = gfx2d::Path {};
            gfx2d::circle(c, 64, 64, 40);
            gfx2d::clip_path(c) { everything(); };
        };
    }, PI * 800, 25);
    check_area("a clip in a clip_path", area() {
        var c = gfx2d::Path {};
        gfx2d::circle(c, 64, 64, 40);
        gfx2d::clip_path(c) { gfx2d::clip_rect(0, 0, 64, 128) { everything(); }; };
    }, PI * 800, 25);
    check_area("a mesh clipped", area() {
        gfx2d::clip_rect(0, 0, 64, 128) {
            gfx2d::polygon([float2 { 0, 0 }, float2 { 128, 0 }, float2 { 128, 128 }, float2 { 0, 128 }], white);
        };
    }, 8192, 2);
    check_area("after the block, none", area() {
        gfx2d::clip_rect(0, 0, 10, 10) { };
        everything();
    }, 16384, 0.5);
    let text_in = block {
        draw(gfx2d::BLACK) {
            gfx2d::clip_rect(0, 0, 40, 128) { gfx2d::text(4, 40, "WWWWWWWW", 32, white); };
        };
        var right = 0;
        for y in W { for x in 41..W { if px[(y * W + x) * 4] > 0 { right++; } } }
        var left = 0;
        for y in W { for x in 0..40 { if px[(y * W + x) * 4] > 0 { left++; } } }
        left > 100 && right == 0
    };
    print("text clipped: ", text_in);

    // Group opacity: two overlapping rects at half opacity as one layer are
    // half white where they overlap, not three quarters.
    draw(gfx2d::BLACK) {
        gfx2d::rect(0, 0, 40, 20, gfx2d::rgba(0xFFFFFF, 0.5));
        gfx2d::rect(20, 0, 40, 20, gfx2d::rgba(0xFFFFFF, 0.5));
        gfx2d::layer(0.5) {
            gfx2d::rect(0, 40, 40, 20, white);
            gfx2d::rect(20, 40, 40, 20, white);
        };
    };
    print("overlap, without a layer ", at(30, 10), "; in a layer at half ", at(30, 50), ", alone ", at(10, 50));

    // Blend modes, over a gray of 128.
    fn blended(mode: i64, c: gfx2d::Color) {
        draw(gfx2d::rgb(0x808080)) {
            gfx2d::layer(gfx2d::LayerDesc { blend: mode as i32 }) { gfx2d::rect(0, 0, 64, 128, c); };
        };
    }
    blended(gfx2d::BLEND_SCREEN, gfx2d::RED);
    print("screen: ", near(10, 10, 255, 128, 128, 255), " outside ", near(100, 10, 128, 128, 128, 255));
    blended(gfx2d::BLEND_MULTIPLY, gfx2d::RED);
    print("multiply: ", near(10, 10, 128, 0, 0, 255), " outside ", near(100, 10, 128, 128, 128, 255));
    blended(gfx2d::BLEND_DIFFERENCE, gfx2d::WHITE);
    print("difference: ", near(10, 10, 127, 127, 127, 255));
    blended(gfx2d::BLEND_DARKEN, gfx2d::rgb(0x40C0FF));
    print("darken: ", near(10, 10, 64, 128, 128, 255));
    blended(gfx2d::BLEND_LIGHTEN, gfx2d::rgb(0x40C0FF));
    print("lighten: ", near(10, 10, 128, 192, 255, 255));
    blended(gfx2d::BLEND_OVERLAY, gfx2d::rgb(0x40C0FF));
    // Overlay over 128/255, just past the middle: a screen by almost nothing.
    print("overlay: ", near(10, 10, 65, 192, 255, 255));
    blended(gfx2d::BLEND_ERASE, gfx2d::WHITE);
    print("erase: ", near(10, 10, 0, 0, 0, 0), " outside ", near(100, 10, 128, 128, 128, 255));
    blended(gfx2d::BLEND_KEEP, gfx2d::WHITE);
    print("keep: ", near(10, 10, 128, 128, 128, 255), " outside ", near(100, 10, 0, 0, 0, 0));
    blended(gfx2d::BLEND_ADD, gfx2d::rgba(0x404040, 1.0));
    print("add: ", near(10, 10, 192, 192, 192, 255));

    // Blur keeps the total and softens the edge.
    let sharp = area() { gfx2d::rect(32, 32, 64, 64, white); };
    let soft = area() { gfx2d::layer(gfx2d::LayerDesc { blur: 4 }) { gfx2d::rect(32, 32, 64, 64, white); }; };
    print("blur: total kept ", abs(sharp - soft) < sharp * 0.01, ", edge ", px[(64 * W + 32) * 4] > 100 &&
          px[(64 * W + 32) * 4] < 155, ", outside ", px[(64 * W + 28) * 4] > 10, ", middle ", near(64, 64, 255, 255, 255, 255));

    // A drop shadow: down and to the right, under the layer.
    draw(gfx2d::WHITE) {
        gfx2d::layer(gfx2d::LayerDesc { shadow: gfx2d::rgba(0x000000, 0.5), shadow_offset: float2 { 10, 10 } }) {
            gfx2d::rect(20, 20, 40, 40, gfx2d::RED);
        };
    };
    print("shadow: under ", near(40, 40, 255, 0, 0, 255), ", beside ", near(65, 65, 128, 128, 128, 255),
          ", none up-left ", near(15, 15, 255, 255, 255, 255));
    // A shape at the target's top edge, translucent, its shadow offset
    // down: above the shadow there is nothing, not the layer's top row
    // again; below, the shadow (a quarter dark, cast by a half-transparent
    // shape) under the shape.
    draw(gfx2d::WHITE) {
        gfx2d::layer(gfx2d::LayerDesc { shadow: gfx2d::rgba(0x000000, 0.5), shadow_offset: float2 { 0, 10 } }) {
            gfx2d::rect(20, 0, 40, 40, gfx2d::rgba(0xFF0000, 0.5));
        };
    };
    print("shadow at the edge: none above its offset ", near(40, 5, 255, 128, 128, 255), ", below it ",
          near(40, 20, 223, 96, 96, 255));

    // A layer in a clip is composited inside the clip only.
    check_area("layer in a clip", area() {
        gfx2d::clip_rect(0, 0, 64, 128) { gfx2d::layer(1.0) { everything(); }; };
    }, 8192, 2);
    let s = gfx2d::stats();
    print("stats: ", s.passes, " passes, ", s.clips, " clip");

    // box_shadow: a gaussian of the box integrates to the box.
    check_area("box_shadow", area() { gfx2d::box_shadow(34, 34, 60, 60, 0, 8, white); }, 3600, 20);
    check_area("box_shadow, rounded", area() { gfx2d::box_shadow(34, 34, 60, 60, 12, 6, white); },
               3600 - (4 - PI) * 144, 25);

    // Multisampled: paths have no fringe, and their area is what the samples
    // say.
    let msaa_area = block {
        gfx2d::begin(target, gfx2d::BLACK, 4);
        gfx2d::star(64, 64, 50, 20, 5, white);
        gfx2d::end();
        px = gfx::read_pixels(target);
        var sum = 0.0;
        for i in W * W { sum += px[i * 4] / 255.0; }
        sum
    };
    check_area("multisampled star", msaa_area, star_area, 15);

    // A layer's passes touch only what it drew: a block that draws nothing
    // leaves no passes, and the blur's and the shadow's reach past the
    // content is kept (their totals are whole).
    draw(gfx2d::BLACK) { gfx2d::layer(0.5) { }; };
    let empty_passes = gfx2d::stats().passes;
    draw(gfx2d::BLACK) { gfx2d::layer(0.5) { everything(); }; };
    print("empty layer: ", empty_passes, " pass, one with content ", gfx2d::stats().passes);
    check_area("blurred in a layer, whole", area() {
        gfx2d::layer(gfx2d::LayerDesc { blur: 4 }) { gfx2d::rect(40, 40, 30, 30, white); };
    }, 900, 5);
    draw(gfx2d::WHITE) {
        gfx2d::layer(gfx2d::LayerDesc { shadow: gfx2d::rgba(0x000000, 1.0), shadow_offset: float2 { 20, 20 },
                                        shadow_blur: 3 }) {
            gfx2d::rect(30, 30, 20, 20, gfx2d::WHITE);
        };
    };
    var dark = 0.0;
    for i in W * W { dark += (255 - px[i * 4]) / 255.0; }
    check_area("a blurred shadow, whole", dark, 400, 5);
    // A blur of sigma 5 and up runs at half resolution, 10 and up at a
    // quarter: the result is the full-resolution one's within a few
    // levels, and its total is kept.
    fn blurred_rect(sigma: f64) -> u8[>..] {
        draw(gfx2d::BLACK) { gfx2d::layer(gfx2d::LayerDesc { blur: sigma }) { gfx2d::rect(40, 40, 30, 30, white); }; };
        copy(px)
    }
    var worst = 0;
    var totals_kept = true;
    for sigma in [6.0, 12.0] {
        gfx2d::BLUR_DOWNSAMPLE_FROM = 1e9;
        let full = blurred_rect(sigma);
        gfx2d::BLUR_DOWNSAMPLE_FROM = 5.0;
        let low = blurred_rect(sigma);
        var total = 0.0;
        for i in W * W {
            let d = abs((full[i * 4] as i64) - (low[i * 4] as i64));
            if d > worst { worst = d; }
            total += low[i * 4] / 255.0;
        }
        if abs(total - 900) > 5 { totals_kept = false; }
    }
    print("blur at half and quarter resolution: within ", worst, " of 255 of the full one, totals kept ", totals_kept);
    draw(gfx2d::BLACK) {
        gfx2d::layer(gfx2d::LayerDesc { blur: 12, shadow: gfx2d::rgba(0x000000, 1.0), shadow_offset: float2 { 4, 4 },
                                        shadow_blur: 14 }) { gfx2d::rect(40, 40, 30, 30, white); };
    };
    print("a blur and a shadow at a quarter: ", gfx2d::stats().passes, " passes, one downsample for both");
    // Nested: the inner layer's shadow counts as drawn by the outer one.
    draw(gfx2d::WHITE) {
        gfx2d::layer(0.5) {
            gfx2d::layer(gfx2d::LayerDesc { shadow: gfx2d::rgba(0x000000, 1.0), shadow_offset: float2 { 40, 40 } }) {
                gfx2d::rect(20, 20, 20, 20, gfx2d::WHITE);
            };
        };
    };
    print("nested shadow at half: ", near(70, 70, 128, 128, 128, 255), " ", near(50, 50, 255, 255, 255, 255));

    // The pool: a layer's textures of another size than the target's go
    // after POOL_IDLE_OTHER frames unused, the target's after POOL_IDLE.
    let small = gfx::render_target(64, 64, gfx::RGBA8);
    gfx2d::draw_into(small, gfx2d::BLACK) { gfx2d::layer(0.5) { everything(); }; };
    fn small_ones() -> i64 {
        var n = 0;
        for t in gfx2d::pool { if t.w == 64 { n++; } }
        n
    }
    let had = small_ones();
    gfx2d::draw_into(target, gfx2d::BLACK) { gfx2d::layer(0.5) { everything(); }; };
    let after_one = small_ones();
    gfx2d::draw_into(target, gfx2d::BLACK) { };
    let after_two = small_ones();
    let kept = gfx2d::pool.len;
    for i in gfx2d::POOL_IDLE - 2 { gfx2d::draw_into(target, gfx2d::BLACK) { }; }
    let still = gfx2d::pool.len;
    gfx2d::draw_into(target, gfx2d::BLACK) { };
    print("pool: ", had, " of another size, ", after_one, " a frame later, ", after_two, " after two; the target's kept ",
          kept > 0 && still > 0, ", ", gfx2d::pool.len, " after ", gfx2d::POOL_IDLE, " frames unused");
    gfx::close();
}
