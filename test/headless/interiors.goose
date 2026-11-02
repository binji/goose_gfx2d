// Large plain rectangles, which gfx2d draws as a ring and an interior
// (gfx2d.goose's BATCH_RINGS and BATCH_SOLIDS), against the same drawn
// whole by the shape shader: the pixels must be the same, with no seam
// where the pieces meet and nothing drawn twice. An antialiased edge pixel
// may round a level the other way (the ring's triangles interpolate the
// local position a little differently from the whole quad); a seam or a
// piece drawn twice would be far more. At fractional places, with
// rounded corners, scaled and flipped, translucent, in every blend mode; and
// turned and aliased, which are never split.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../..";

let W = 256;

var target: gfx::Texture;

fn scene() {
    gfx2d::draw_into(target, gfx2d::rgb(0x406080)) {
        gfx2d::rect(10.3, 12.6, 120.4, 90.7, gfx2d::rgba(0xff8020, 0.37));
        gfx2d::rect(60.5, 40.5, 150.0, 100.0, gfx2d::rgba(0x20ff80, 0.6));
        gfx2d::rounded_rect(20.25, 120.75, 200.5, 110.5, 18.5, gfx2d::rgba(0xffffff, 0.45));
        gfx2d::rounded_rect(140.1, 10.9, 100.0, 220.0, float4 { 0.0, 30.0, 4.0, 60.0 }, gfx2d::rgba(0x8020ff, 0.5));
        gfx2d::rect(0, 0, W as f64, W as f64, gfx2d::rgba(0x000000, 0.2));
        gfx2d::translate(128.4, 128.7) {
            gfx2d::scale(1.7, 0.9) { gfx2d::rect(-50.2, -60.3, 90.0, 120.0, gfx2d::rgba(0xff0000, 0.3)); };
            gfx2d::scale(-1.0, 1.0) { gfx2d::rounded_rect(-30.6, -90.1, 110.0, 80.0, 9.0, gfx2d::rgba(0x00ff00, 0.3)); };
            gfx2d::scale(1.0, -2.0) { gfx2d::rect(-100.0, -40.0, 120.0, 45.0, gfx2d::rgba(0x0000ff, 0.25)); };
            gfx2d::rotate(0.3) { gfx2d::rect(-60.0, -60.0, 120.0, 120.0, gfx2d::rgba(0xffff00, 0.3)); };
        };
        gfx2d::antialias(false) { gfx2d::rect(30.5, 30.5, 100.25, 70.75, gfx2d::rgba(0x00ffff, 0.4)); };
        gfx2d::rect(5.5, 150.2, 110.0, 90.0, gfx2d::with_blend(gfx2d::solid(gfx2d::rgba(0xff0000, 0.5)), gfx2d::BLEND_ADD));
        gfx2d::rect(70.3, 160.8, 120.0, 80.0, gfx2d::with_blend(gfx2d::solid(gfx2d::rgb(0x808080)), gfx2d::BLEND_MULTIPLY));
        gfx2d::rect(150.7, 150.3, 90.0, 95.0, gfx2d::with_blend(gfx2d::solid(gfx2d::rgba(0x00ff00, 0.5)), gfx2d::BLEND_REPLACE));
        gfx2d::rect(100.0, 100.0, 64.0, 64.0, gfx2d::BLACK);
    };
}

fn main() {
    guard gfx::open_headless(W, W) else {
        print("gfx: ", gfx::error());
        return;
    }
    target = gfx::render_target(W, W, gfx::RGBA8);

    gfx2d::solid_min_pixels = 1e30;
    scene();
    let whole = gfx::read_pixels(target);
    let whole_draws = gfx2d::stats().draws;

    gfx2d::solid_min_pixels = 48.0;
    scene();
    let split = gfx::read_pixels(target);
    let split_draws = gfx2d::stats().draws;

    var most = 0;
    for i in whole.len { most = max(most, abs(whole[i] as i64 - split[i] as i64)); }
    print("split into more draws: ", split_draws > whole_draws);
    print("the same within a level: ", most <= 1);
}
