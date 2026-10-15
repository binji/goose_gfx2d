// gfx2d's paints drawn headless and read back: gradients of every kind and
// spread, paints pinned to the screen, images (whole, scaled, parts of one,
// flipped, tinted, as patterns), nine-slices, blend modes, opacity, and
// how paints, ramps and batches are shared.
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
fn red(x: i64, y: i64) -> i64 { px[(y * W + x) * 4] }
// Whether the red channel at (x, y) is within 2 of v.
fn red_near(x: i64, y: i64, v: f64) -> bool { abs(red(x, y) - v) <= 2.0 }

// A 4x4 texture: texel (x, y) is (x * 60, y * 60, 200, 255).
fn test_texture() -> gfx::Texture {
    let t = gfx::texture2d(4, 4);
    var data: u8[>..] = [];
    for y in 4 {
        for x in 4 { data.append([(x * 60) as u8, (y * 60) as u8, 200, 255]); }
    }
    gfx::update_texture(t, data);
    t
}
fn texel(x: i64, y: i64) -> u8[>..] { str(x * 60, ",", y * 60, ",200,255") }

fn main() {
    guard gfx::open_headless(W, W) else {
        print("gfx: ", gfx::error());
        return;
    }
    target = gfx::render_target(W, W, gfx::RGBA8);
    let black = gfx2d::BLACK;
    let white = gfx2d::WHITE;

    // Linear: black at x 0 to white at x 128, so pixel x (center x + 0.5)
    // is (x + 0.5) / 128 of the way.
    draw(black) { gfx2d::rect(0, 0, W, 4, gfx2d::linear(0, 0, W, 0, black, white)); };
    var off = 0;
    for x in W {
        if !red_near(x, 1, (x + 0.5) / W * 255) { off++; }
    }
    print("linear: ", off, " pixels off");

    // Spreads past the end at x 32.
    fn spread_paint(mode: i64) -> gfx2d::Paint {
        var g = gfx2d::linear_gradient(0, 0, 32, 0, [gfx2d::stop(0, black), gfx2d::stop(1, white)]);
        g.spread = mode as i32;
        gfx2d::paint(g)
    }
    draw(black) {
        gfx2d::rect(0, 0, W, 4, spread_paint(gfx2d::SPREAD_PAD));
        gfx2d::rect(0, 4, W, 4, spread_paint(gfx2d::SPREAD_REPEAT));
        gfx2d::rect(0, 8, W, 4, spread_paint(gfx2d::SPREAD_REFLECT));
    };
    print("pad: ", red(40, 1), "; repeat: ", red(40, 5) == red(8, 5), "; reflect: ",
          red(40, 9) == red(23, 9));

    // Radial: white in the middle, black at radius 40.
    draw(black) { gfx2d::rect(0, 0, W, W, gfx2d::radial(64, 64, 40, white, black)); };
    print("radial: center ", red_near(64, 64, 255 * (1 - 0.7071 / 40)), ", halfway ",
          red_near(84, 64, 255 * (1 - 20.5 / 40)), ", outside ", red(110, 64));
    // Its focal point off center: white is there instead.
    draw(black) {
        gfx2d::rect(0, 0, W, W, gfx2d::paint(gfx2d::radial_gradient(64, 64, 40, 44, 64,
                                             [gfx2d::stop(0, white), gfx2d::stop(1, black)])));
    };
    print("focal: ", red(44, 64) > 250, " ", red(64, 64) < red(44, 64), " edge ",
          red(24, 64) < 8 && red(104, 64) < 8);

    // Conic: black to white clockwise from +x.
    draw(black) {
        gfx2d::rect(0, 0, W, W, gfx2d::paint(gfx2d::conic_gradient(64, 64, 0,
                                             [gfx2d::stop(0, black), gfx2d::stop(1, white)])));
    };
    print("conic: right ", red(100, 64) < 3, ", below ", red_near(64, 100, 64),
          ", left ", red_near(27, 64, 128), ", above ", red_near(64, 27, 191));

    // A local paint moves with the shape; a screen one stays.
    draw(black) {
        gfx2d::translate(64, 0) {
            gfx2d::rect(0, 0, 64, 4, gfx2d::linear(0, 0, W, 0, black, white));
            var screen = gfx2d::linear(0, 0, W, 0, black, white);
            screen.space = gfx2d::SPACE_SCREEN;
            gfx2d::rect(0, 4, 64, 4, screen);
        };
    };
    print("local: ", red_near(64, 1, 0.5 / W * 255), "; screen: ", red_near(64, 5, 64.5 / W * 255));

    // Gradients on any shape, under any transform.
    draw(black) {
        gfx2d::translate(64, 64) {
            gfx2d::rotate(PI / 2) {
                gfx2d::circle(0, 0, 50, gfx2d::linear(-50, 0, 50, 0, black, white));
            };
        };
    };
    print("rotated: top ", red(64, 16) < 20, ", bottom ", red(64, 110) > 235);

    // Images.
    let tex = test_texture();
    draw(black) { gfx2d::image(tex, 10, 10, gfx2d::WHITE, gfx2d::FILTER_NEAREST); };
    var same = true;
    for y in 4 { for x in 4 { if at(10 + x, 10 + y) != texel(x, y) { same = false; } } }
    print("image: ", same, "; around it ", at(9, 10), " ", at(14, 13));
    draw(black) {
        gfx2d::image(tex, gfx2d::rect_of(0, 0, 8, 8), gfx2d::WHITE, gfx2d::FILTER_NEAREST);
    };
    print("scaled: ", at(0, 0) == texel(0, 0) && at(1, 1) == texel(0, 0) && at(2, 0) == texel(1, 0)
          && at(7, 7) == texel(3, 3));
    draw(black) {
        gfx2d::image(tex, gfx2d::rect_of(0, 0, 2, 2), gfx2d::rect_of(2, 1, 2, 2));
        gfx2d::image(tex, gfx2d::rect_of(14, 0, -4, 4), gfx2d::WHITE, gfx2d::FILTER_NEAREST);
    };
    print("part: ", at(0, 0) == texel(2, 1) && at(1, 1) == texel(3, 2), "; flipped: ",
          at(10, 0) == texel(3, 0) && at(13, 0) == texel(0, 0));
    draw(black) { gfx2d::image(tex, 0, 0, gfx2d::rgb(0x808080), gfx2d::FILTER_NEAREST); };
    print("tinted: ", at(3, 3), " of ", texel(3, 3));
    // With a Paint: its blend mode and opacity, and its gradient multiplying
    // the image, whose own image it replaces.
    draw(gfx2d::BLUE) {
        gfx2d::image(tex, 0, 0, gfx2d::with_blend(gfx2d::solid(white), gfx2d::BLEND_ADD), gfx2d::FILTER_NEAREST);
        gfx2d::image(tex, gfx2d::rect_of(10, 0, 4, 4), gfx2d::with_opacity(gfx2d::solid(white), 0.5),
                     gfx2d::FILTER_NEAREST);
        var g = gfx2d::linear(0, 0, W, 0, white, black);
        g.image = gfx2d::image_pattern(tex);        // replaced by the image drawn
        gfx2d::image(tex, gfx2d::rect_of(0, 10, W, 4), gfx2d::rect_of(3, 3, 1, 1), g, gfx2d::FILTER_NEAREST);
    };
    print("paint: added ", at(3, 3), ", at half ", at(13, 3), ", gradient ",
          red_near(100, 11, 180 * (1 - 100.5 / W)), " blue ", px[(11 * W + 100) * 4 + 2]);
    draw(black) {
        gfx2d::rect(0, 0, 16, 16, gfx2d::paint(gfx2d::image_pattern(tex, gfx2d::IDENTITY,
                                               gfx2d::WRAP_REPEAT, gfx2d::FILTER_NEAREST)));
        gfx2d::rect(20, 0, 16, 16, gfx2d::paint(gfx2d::image_pattern(tex, gfx2d::translation(20, 0),
                                                gfx2d::WRAP_DECAL, gfx2d::FILTER_NEAREST)));
        gfx2d::rect(40, 0, 16, 16, gfx2d::paint(gfx2d::image_pattern(tex, gfx2d::translation(40, 0),
                                                gfx2d::WRAP_MIRROR, gfx2d::FILTER_NEAREST)));
    };
    print("repeat: ", at(5, 6) == texel(1, 2), "; decal: ", at(21, 1) == texel(1, 1), " ", at(26, 6),
          "; mirror: ", at(44, 0) == texel(3, 0) && at(47, 0) == texel(0, 0));

    // A gradient times an image: white texture, so the gradient.
    let white_tex = gfx::texture2d(2, 2);
    gfx::update_texture(white_tex, [255 as u8; 16]);
    draw(black) {
        gfx2d::rect(0, 0, W, 4, gfx2d::Paint {
            gradient: gfx2d::linear_gradient(0, 0, W, 0, [gfx2d::stop(0, white), gfx2d::stop(1, black)]),
            image: gfx2d::image_pattern(white_tex),
        });
    };
    print("gradient x image: ", red_near(0, 1, 255 * (1 - 0.5 / W)), " ", red_near(100, 1, 255 * (1 - 100.5 / W)));

    // Nine-slice: a 6x6 texture, a 2-pixel red border round green, drawn
    // 30x14: the border stays 2 pixels.
    let frame_tex = gfx::texture2d(6, 6);
    var fdata: u8[>..] = [];
    for y in 6 {
        for x in 6 {
            let border = x < 2 || y < 2 || x >= 4 || y >= 4;
            fdata.append(if border { [255 as u8, 0, 0, 255] } else { [0 as u8, 255, 0, 255] });
        }
    }
    gfx::update_texture(frame_tex, fdata);
    draw(black) {
        gfx2d::nine_slice(frame_tex, gfx2d::rect_of(10, 10, 30, 14), float4 { 2, 2, 2, 2 },
                          gfx2d::WHITE, gfx2d::FILTER_NEAREST);
    };
    print("nine-slice: ", at(10, 10), " ", at(11, 20), " ", at(12, 12), " ", at(37, 21), " ",
          at(38, 22), " ", at(39, 23), " ", at(40, 24));

    // At fractional places, the pieces still meet with no seam.
    let white8 = gfx::texture2d(8, 8);
    gfx::update_texture(white8, [255 as u8; 256]);
    draw(black) {
        gfx2d::nine_slice(white8, gfx2d::rect_of(10.3, 10.6, 30.4, 20.2), float4 { 2.5, 2.5, 2.5, 2.5 });
    };
    var seams = 0;
    for y in 12..30 { for x in 12..40 { if red(x, y) != 255 { seams++; } } }
    print("nine-slice seams: ", seams);

    // Blend modes.
    draw(gfx2d::BLUE) {
        gfx2d::rect(0, 0, 8, 8, gfx2d::with_blend(gfx2d::solid(gfx2d::RED), gfx2d::BLEND_ADD));
        gfx2d::rect(8, 0, 8, 8, gfx2d::with_blend(gfx2d::solid(gfx2d::rgba(0xFF0000, 0.5)),
                                                  gfx2d::BLEND_ADD));
        gfx2d::rect(16, 0, 8, 8, gfx2d::with_blend(gfx2d::solid(gfx2d::rgb(0x808080)),
                                                   gfx2d::BLEND_MULTIPLY));
        gfx2d::rect(24, 0, 8, 8, gfx2d::with_blend(gfx2d::solid(gfx2d::rgba(0xFF0000, 0.5)),
                                                   gfx2d::BLEND_REPLACE));
        gfx2d::rect(32, 0, 8, 8, gfx2d::with_opacity(gfx2d::solid(gfx2d::RED), 0.5));
    };
    print("add: ", at(4, 4), "; half add: ", at(12, 4), "; multiply: ", at(20, 4), "; replace: ",
          at(28, 4), "; opacity: ", at(36, 4));

    // Sharing: one paint for many shapes, one ramp for one gradient's
    // stops wherever it is (and none baked again the next frame, since
    // ramps are kept), one paint for images of one size wherever they
    // are, one draw while only solid shapes come between images of one
    // texture.
    gfx2d::reset_ramps();
    fn sharing() {
        let p = gfx2d::radial(0, 0, 10, white, black);
        for i in 100 { gfx2d::circle(i, i, 3, p); }
        gfx2d::rect(0, 0, 4, 4, gfx2d::linear(0, 0, 4, 0, white, black));
        gfx2d::rect(0, 0, 4, 4, gfx2d::linear(9, 0, 4, 4, white, black));
        gfx2d::image(tex, 0, 0);
        gfx2d::circle(5, 5, 5, gfx2d::RED);
        gfx2d::image(tex, 10, 0);
    }
    draw(black) { sharing(); };
    var s = gfx2d::stats();
    print("shared: ", s.instances, " instances, ", s.paints, " paints, ", s.ramps, " ramps, ",
          s.draws, " draw");
    let first = copy(px);
    draw(black) { sharing(); };
    s = gfx2d::stats();
    print("the next frame: ", s.ramps, " ramps baked, the same pixels from the kept one ", px == first);
    // Two paints taking turns are two records, not one a shape; a color at
    // an opacity is no record, its opacity in the instance's color.
    draw(black) {
        let a = gfx2d::radial(0, 0, 10, white, black);
        let b = gfx2d::linear(0, 0, 4, 0, white, black);
        for i in 100 { gfx2d::circle(i, i, 3, if i % 2 == 0 { a } else { b }); }
        for i in 10 { gfx2d::rect(i * 4, 100, 4, 4, gfx2d::with_opacity(gfx2d::solid(white), 0.5)); }
        gfx2d::polygon([float2 { 50, 100 }, float2 { 60, 100 }, float2 { 60, 110 }], gfx2d::with_opacity(gfx2d::solid(white), 0.25));
    };
    s = gfx2d::stats();
    print("by turns: ", s.paints, " paints for two taking turns and solids at an opacity, which draw ", at(2, 102),
          " and ", at(59, 104));
    // The ramp atlas full: the gradients past the last row are drawn as
    // their middle color this frame, and the atlas starts over next frame
    // with them in it.
    gfx2d::RAMP_MAX_ROWS = 4;
    gfx2d::reset_ramps();
    fn ramps(from: i64) {
        for i in from..5 {
            let c = gfx2d::rgb(0x202020 * (i + 1));
            gfx2d::rect(i * 8, 0, 8, 4, gfx2d::linear(i * 8, 0, i * 8 + 8, 0, c, black));
        }
    }
    draw(black) { ramps(0); };
    s = gfx2d::stats();
    print("full: ", s.ramps, " ramps, the fifth its middle color ", at(33, 1), " ", at(39, 1), ", full ", gfx2d::ramps_full);
    draw(black) { ramps(4); };
    s = gfx2d::stats();
    print("after: ", s.ramps, " ramp baked, the fifth a gradient ", red(33, 1) > 100 && red(39, 1) < 40 && red(39, 1) > 0,
          ", full ", gfx2d::ramps_full);
    gfx2d::RAMP_MAX_ROWS = 4096;
    gfx2d::reset_ramps();
    draw(black) {
        gfx2d::image(tex, 0, 0);
        gfx2d::image(white_tex, 10, 0);
        gfx2d::image(tex, 20, 0);
        gfx2d::image(tex, 30, 0, gfx2d::WHITE, gfx2d::FILTER_NEAREST);
        gfx2d::rect(0, 0, 4, 4, gfx2d::with_blend(gfx2d::solid(white), gfx2d::BLEND_ADD));
    };
    s = gfx2d::stats();
    print("batches: ", s.draws, " draws for a texture, another, the first again, another filter and a blend");
    gfx::close();
}
