// gfx2d's pixel-art tools and camera, headless: antialiasing off (no partly
// covered pixels, images nearest), a pixel canvas scaled up by a whole
// number and centered, a camera placing the world, and the mouse in a
// transform's space.
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
fn at(x: i64, y: i64) -> u8[>..] {
    let i = (y * W + x) * 4;
    str(px[i], ",", px[i + 1], ",", px[i + 2], ",", px[i + 3])
}
// How many pixels have red neither 0 nor 255, and how many 255.
fn partial_full() -> i64, i64 {
    var partial = 0;
    var full = 0;
    for i in W * W {
        let r = px[i * 4];
        if r == 255 { full++; } else if r != 0 { partial++; }
    }
    return partial, full;
}

fn main() {
    guard gfx::open_headless(W, W) else {
        print("gfx: ", gfx::error());
        return;
    }
    target = gfx::render_target(W, W, gfx::RGBA8);
    let white = gfx2d::WHITE;

    // Antialiasing off: every pixel covered or not.
    draw(gfx2d::BLACK) {
        gfx2d::antialias(false) {
            gfx2d::circle(40.3, 40.7, 25, white);
            gfx2d::text(4, 80, "Pixels!", 24, white);
            gfx2d::star(100, 100, 5, 25, 10, white);
            gfx2d::translate(100, 30) { gfx2d::rotate(0.4) { gfx2d::rounded_rect(-15, -10, 30, 20, 5, white); }; };
        };
    };
    let partial, full = partial_full();
    print("aliased: ", partial, " partly covered pixels, ", full > 2500, " covered");
    draw(gfx2d::BLACK) { gfx2d::circle(40.3, 40.7, 25, white); };
    let soft, _ = partial_full();
    print("antialiased, by contrast: ", soft > 50);
    // set_antialias and the block restore: after the block, on again.
    draw(gfx2d::BLACK) {
        gfx2d::antialias(false) { };
        gfx2d::circle(40.3, 40.7, 25, white);
    };
    let after, _ = partial_full();
    print("after the block: ", after > 50);

    // Images default to nearest with antialiasing off.
    let tex = gfx::texture2d(2, 2);
    gfx::update_texture(tex, [255 as u8, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255]);
    draw(gfx2d::BLACK) {
        gfx2d::antialias(false) { gfx2d::image(tex, gfx2d::rect_of(0, 0, 8, 8)); };
        gfx2d::image(tex, gfx2d::rect_of(16, 0, 8, 8));
    };
    print("nearest: ", at(3, 3), " ", at(4, 3), " ", at(3, 4), "; linear: ", at(19, 3) != "255,0,0,255");

    // A pixel canvas of 40 x 30 in 128 x 128: scaled 3 times, to 120 x 90,
    // at (4, 19); the rest the frame's own clear color.
    draw(gfx2d::rgb(0x202020)) {
        gfx2d::pixel_canvas(40, 30, gfx2d::BLUE) {
            gfx2d::rect(0, 0, 1, 1, gfx2d::RED);
            gfx2d::rect(39, 29, 1, 1, gfx2d::LIME);
            gfx2d::circle(20, 15, 6, white);
        };
    };
    let fit = gfx2d::pixel_canvas_fit(40, 30, W, W);
    print("canvas fit: ", fit.a, "x at ", fit.tx, ", ", fit.ty);
    print("canvas: corner ", at(4, 19), " ", at(6, 21), " next ", at(7, 21), "; far corner ", at(121, 106),
          " ", at(123, 108), "; letterbox ", at(1, 1), " ", at(64, 120));
    var blocky = true;
    for cy in 30 {
        for cx in 40 {
            let first = at(4 + cx * 3, 19 + cy * 3);
            for dy in 3 { for dx in 3 { if at(4 + cx * 3 + dx, 19 + cy * 3 + dy) != first { blocky = false; } } }
        }
    }
    print("each canvas pixel a 3x3 block: ", blocky);

    // A camera: the world's origin in the middle, two pixels a unit.
    draw(gfx2d::BLACK) {
        gfx2d::camera(gfx2d::Camera2D { center: float2 { 0, 0 }, zoom: 2 }) {
            gfx2d::circle(10, 0, 5, white);
        };
    };
    print("camera: ", at(84, 64), " ", at(64, 64), " ", at(84, 58), " ", at(84, 50));

    // The mouse in a transform's space.
    gfx::inject_mouse(50, 60, 0, false);
    gfx::frame();
    var local = float2_0;
    draw(gfx2d::BLACK) {
        gfx2d::translate(10, 20) { gfx2d::scale(2) { local = gfx2d::mouse_local(); }; };
    };
    print("mouse_local: ", local);

    // A base scale: the frame's units drawn that many pixels each, under
    // the transform blocks, and to_local dividing it out.
    var inside = float2 { 0, 0 };
    var scaled = 0.0;
    gfx2d::draw_into(target, gfx2d::BLACK, 1, 2) {
        gfx2d::rect(10, 10, 20, 20, gfx2d::WHITE);
        gfx2d::translate(5, 0) { inside = gfx2d::to_local(float2 { 40, 40 }); };
        scaled = gfx2d::current_transform().a;
    };
    px = gfx::read_pixels(target);
    print("scale 2: ", at(19, 19), " ", at(20, 20), " ", at(59, 59), " ", at(60, 60), "; to_local ", inside,
          "; the transform ", scaled, "x; kept ", gfx2d::current_scale());
    gfx2d::set_scale(1);
    gfx::close();
}
