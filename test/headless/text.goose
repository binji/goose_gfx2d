// gfx2d's text drawn headless and read back: where its ink lands against
// what measure_text says, alignment and baselines, outlines, a gradient
// across text, turned text, and glyphs shared across sizes in the atlas.
import std;
import vec;
import math;
import gfx;
import gfx2d from "../..";

let W = 256;
let H = 128;

var target: gfx::Texture;
var px: u8[>..] = [];

// The bounds of the ink (any pixel not white) drawn by the block on white:
// x0, y0, x1, y1, and how many pixels.
struct Box { x: i64, y: i64, z: i64, w: i64 }

fn ink<F>() -> Box, i64 {
    gfx2d::draw_into(target, gfx2d::WHITE) { F(); };
    px = gfx::read_pixels(target);
    var b = Box { W, H, -1, -1 };
    var n = 0;
    for y in H {
        for x in W {
            let i = (y * W + x) * 4;
            if px[i] < 250 || px[i + 1] < 250 || px[i + 2] < 250 {
                b = Box { min(b.x, x), min(b.y, y), max(b.z, x), max(b.w, y) };
                n++;
            }
        }
    }
    return b, n;
}

fn main() {
    guard gfx::open_headless(W, H) else {
        print("gfx: ", gfx::error());
        return;
    }
    target = gfx::render_target(W, H, gfx::RGBA8);
    let black = gfx2d::BLACK;

    // The ink is inside the measured box (a pixel of antialiasing aside),
    // and fills most of its width.
    let size = gfx2d::measure_text("Hello, world", 32);
    let b, n = ink() { gfx2d::text(10, 10, "Hello, world", 32, black); };
    print("ink: ", n > 500, "; inside the box: ", b.x >= 9 && b.y >= 9 && b.z <= 10 + size.x + 1 &&
          b.w <= 10 + size.y + 1, "; most of its width: ", b.z - b.x > size.x * 0.9);

    // Centered on x 128; right-aligned to x 246.
    let cb, cn = ink() {
        gfx2d::text(128, 10, "centered", gfx2d::TextStyle { size: 24, align: gfx2d::ALIGN_CENTER }, black);
    };
    print("centered: ", abs((cb.x + cb.z) / 2.0 - 128) <= 2);
    let rb, rn = ink() {
        gfx2d::text(246, 10, "right", gfx2d::TextStyle { size: 24, align: gfx2d::ALIGN_RIGHT }, black);
    };
    print("right-aligned: ", abs(rb.z - 246) <= 3);
    // With a wrap width, aligned within the box from x to x + wrap_width.
    let wc, wcn = ink() {
        gfx2d::text(20, 10, "aa bb", gfx2d::TextStyle { size: 24, align: gfx2d::ALIGN_CENTER, wrap_width: 200 }, black);
    };
    let wr, wrn = ink() {
        gfx2d::text(20, 10, "aa bb", gfx2d::TextStyle { size: 24, align: gfx2d::ALIGN_RIGHT, wrap_width: 200 }, black);
    };
    print("in the wrap box: centered ", abs((wc.x + wc.z) / 2.0 - 120) <= 2, ", right-aligned ", abs(wr.z - 220) <= 3);

    // Baselines: at the alphabetic baseline, letters without descenders sit
    // just above y; at the middle, the ink straddles it; at the bottom, it is
    // all above.
    let ab, an = ink() {
        gfx2d::text(10, 80, "Hxe", gfx2d::TextStyle { size: 40, baseline: gfx2d::BASELINE_ALPHABETIC }, black);
    };
    print("alphabetic: the ink ends at y 80 ", abs(ab.w - 80) <= 1);
    let mb, mn = ink() {
        gfx2d::text(10, 64, "Hxe", gfx2d::TextStyle { size: 40, baseline: gfx2d::BASELINE_MIDDLE }, black);
    };
    print("middle: straddles ", mb.y < 64 && mb.w > 64);
    let bb, bn = ink() {
        gfx2d::text(10, 100, "Hxe", gfx2d::TextStyle { size: 40, baseline: gfx2d::BASELINE_BOTTOM }, black);
    };
    print("bottom: above ", bb.w <= 100);

    // An outline of glyphs whose strokes are wider than it covers less than
    // they do, around the same place.
    let ob, on = ink() {
        gfx2d::text(10, 0, "OIO", gfx2d::TextStyle { size: 96, outline: 1 }, black);
    };
    let fb, fn_ = ink() { gfx2d::text(10, 0, "OIO", 96, black); };
    print("outline: less ink ", on < fn_, ", same place ", abs(ob.x - fb.x) <= 2 && abs(ob.z - fb.z) <= 2);

    // A gradient across the text: red at its left, blue at its right.
    gfx2d::draw_into(target, gfx2d::WHITE) {
        gfx2d::text(10, 10, "IIIIIIIIIIIIIIIIIIII", 48, gfx2d::linear(10, 0, 230, 0, gfx2d::RED, gfx2d::BLUE));
    };
    px = gfx::read_pixels(target);
    var left = Box { 0, 0, 0, 0 };
    var right = Box { 0, 0, 0, 0 };
    for y in H {
        for x in W {
            let i = (y * W + x) * 4;
            if px[i] < 250 || px[i + 2] < 250 {
                if x < 60 && px[i] > px[i + 2] { left.x++; }
                if x < 60 { left.y++; }
                if x > 180 && px[i + 2] > px[i] { right.x++; }
                if x > 180 { right.y++; }
            }
        }
    }
    print("gradient: red on the left ", left.x * 10 > left.y * 9, ", blue on the right ", right.x * 10 > right.y * 9);

    // Turned a quarter, a line of text stands up.
    let tb, tn = ink() {
        gfx2d::translate(128, 10) { gfx2d::rotate(PI / 2) { gfx2d::text(0, 0, "standing", 16, black); }; };
    };
    print("turned: taller than wide ", tb.w - tb.y > (tb.z - tb.x) * 2);

    // A glyph is rasterized once, whatever size it is drawn at.
    let before = gfx2d::glyph_count;
    gfx2d::draw_into(target, gfx2d::WHITE) {
        for k in 1..9 { gfx2d::text(0, 0, "QQQQ", k * 6, black); }
    };
    print("one Q in the atlas for 32 drawn: ", gfx2d::glyph_count - before);
    // Spaces take room but draw nothing.
    let sb, sn = ink() { gfx2d::text(10, 10, "    ", 32, black); };
    print("spaces: ", sn, " pixels of ink");
    gfx::close();
}
