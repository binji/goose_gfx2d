// gfx2d's showcase: one scene using a wide spread of the API (shapes and
// outlines, transforms, gradients and images, blend modes, paths, strokes
// and dashes, text, clips, layers with blur and shadow, box shadows, a pixel
// canvas, multisampling), checking itself by reading pixels back, and
// saving screenshots. test/window/run_window_test.py runs it every way the
// machine can and compares the screenshots.
//
//   goose test/window/gfx2d_showcase.goose -- --frames 60 --out shots
//
// It opens a window (GOOSE_GFX_HEADLESS=1: none), and prints `ok` per
// check and `checks: N failed` at the end; it exits after --frames frames.
import std;
import vec;
import math;
import os;
import gfx;
import gfx2d from "../..";

let W = 1280;
let H = 720;

var failed = 0;
fn check(name: const u8[:], ok: bool) {
    print(if ok { "ok    " } else { "FAIL  " }, name);
    if !ok { failed++; }
}

fn scene(t: f64, grain: gfx::Texture) {
    let ink = gfx2d::rgb(0x22223B);
    let accent = gfx2d::palette(8, 0.15);

    // Shapes, filled and outlined, some turned.
    gfx2d::rect(20, 20, 100, 60, accent[0]);
    gfx2d::rounded_rect(140, 20, 100, 60, float4 { 20, 0, 20, 0 }, accent[1]);
    gfx2d::ellipse(310, 50, 50, 30, accent[2]);
    gfx2d::circle_outline(410, 50, 30, 3, ink);
    gfx2d::pie(490, 50, 32, -PI / 2, -PI / 2 + 4, accent[3]);
    gfx2d::arc(570, 50, 28, PI * 0.8, PI * 2.2, 8, accent[4], gfx2d::CAP_ROUND);
    gfx2d::line(620, 30, 700, 70, 6, ink, gfx2d::CAP_ROUND);
    gfx2d::translate(760, 50) { gfx2d::rotate(t) { gfx2d::rect_outline(-25, -25, 50, 50, 2, accent[5]); }; };

    // Paints: a gradient times a texture, conic and radial gradients.
    gfx2d::rounded_rect(20, 100, 220, 100, 14, gfx2d::Paint {
        gradient: gfx2d::linear_gradient(20, 100, 240, 200, [gfx2d::stop(0, gfx2d::rgb(0xFF8800)),
                                                              gfx2d::stop(1, gfx2d::rgb(0x2200AA))]),
        image: gfx2d::image_pattern(grain, gfx2d::scaling(0.5)),
    });
    var wheel: gfx2d::Stop[>..] = [];
    for k in 7 { wheel.push(gfx2d::stop(k / 6.0, gfx2d::hsv(k / 6.0, 0.8, 1.0))); }
    gfx2d::circle(310, 150, 50, gfx2d::paint(gfx2d::conic_gradient(310, 150, 0, wheel)));
    gfx2d::circle(420, 150, 50, gfx2d::radial(400, 130, 60, gfx2d::WHITE, gfx2d::NAVY));

    // Paths: a heart of cubics, a pentagram by each rule, a dashed stroke.
    var heart = gfx2d::Path {};
    gfx2d::move_to(heart, 540, 195);
    gfx2d::cubic_to(heart, 470, 150, 500, 100, 540, 130);
    gfx2d::cubic_to(heart, 580, 100, 610, 150, 540, 195);
    gfx2d::close(heart);
    gfx2d::fill(heart, gfx2d::rgb(0xC9184A));
    gfx2d::stroke(heart, 2, ink);
    var star = gfx2d::Path {};
    for k in 5 {
        let a = -PI / 2 + k * 2 * TAU / 5;
        if k == 0 { gfx2d::move_to(star, 680 + 45 * cos(a), 150 + 45 * sin(a)); }
        else { gfx2d::line_to(star, 680 + 45 * cos(a), 150 + 45 * sin(a)); }
    }
    gfx2d::close(star);
    gfx2d::fill(star, accent[6]);
    gfx2d::translate(100, 0) { gfx2d::fill(star, accent[7], gfx2d::EVEN_ODD); };
    var loop_path = gfx2d::Path {};
    gfx2d::circle(loop_path, 920, 150, 45);
    gfx2d::stroke(loop_path, gfx2d::Stroke { width: 4, cap: gfx2d::CAP_ROUND, dash: [10, 6],
                                             dash_offset: (t * 20) as f32 }, ink);
    var series: float2[>..] = [];
    for k in 60 { series.push(float2 { 1000 + k * 4, (150 + 30 * sin(k * 0.3 + t)) as f32 }); }
    gfx2d::polyline(series, 3, accent[2], gfx2d::CAP_ROUND, gfx2d::JOIN_ROUND);

    // Text: sizes, alignment, wrapping, gradient text, an outline.
    gfx2d::text(20, 230, "gfx2d showcase", gfx2d::TextStyle { size: 40, outline: 3 }, gfx2d::rgb(0xA8DADC));
    gfx2d::text(20, 230, "gfx2d showcase", 40, gfx2d::linear(20, 0, 320, 0, gfx2d::RED, gfx2d::BLUE));
    gfx2d::text(20, 285, "The quick brown fox jumps over the lazy dog, in Inter at 16px; kerning: AV To Wa.",
                gfx2d::TextStyle { size: 16, wrap_width: 420 }, ink);
    gfx2d::translate(560, 270) { gfx2d::rotate(-0.2) {
        gfx2d::text(0, 0, "turned", gfx2d::TextStyle { size: 28, align: gfx2d::ALIGN_CENTER,
                                                       baseline: gfx2d::BASELINE_MIDDLE }, accent[3]);
    }; };

    // Clips and layers: a clipped image, group opacity, a blend mode, a
    // blurred and shadowed card, box shadows.
    gfx2d::clip_circle(80, 420, 60) { gfx2d::image(grain, gfx2d::rect_of(0, 340, 200, 200)); };
    gfx2d::layer(0.5) {
        for k in 3 { gfx2d::circle(200 + k * 30, 420, 40, accent[k]); }
    };
    gfx2d::rect(330, 360, 140, 120, gfx2d::linear(330, 0, 470, 0, gfx2d::rgb(0x003049), gfx2d::rgb(0xFCBF49)));
    gfx2d::layer(gfx2d::LayerDesc { blend: gfx2d::BLEND_SCREEN }) { gfx2d::circle(400, 420, 45, gfx2d::RED); };
    gfx2d::layer(gfx2d::LayerDesc { shadow: gfx2d::rgba(0x000000, 0.4), shadow_offset: float2 { 6, 8 },
                                    shadow_blur: 6 }) {
        gfx2d::rounded_rect(500, 360, 180, 120, 14, gfx2d::WHITE);
        gfx2d::clip_rounded_rect(500, 360, 180, 120, 14) {
            gfx2d::rect(500, 360, 180, 36, accent[4]);
        };
        gfx2d::text(516, 410, "card", 22, ink);
    };
    gfx2d::layer(gfx2d::LayerDesc { blur: 3 }) { gfx2d::text(720, 400, "blurred", 36, ink); };
    for k in 3 {
        gfx2d::box_shadow(900 + k * 120, 380, 90, 60, 10, 4 + k * 10, gfx2d::rgba(0x000000, 0.5));
        gfx2d::rounded_rect(900 + k * 120, 376, 90, 60, 10, gfx2d::WHITE);
    }

}

fn main() {
    var frames = 60;
    var out: u8[>..] = [];
    let argv = args();
    var i = 1;
    while i + 1 < argv.len {
        if argv[i] == "--frames" {
            let n, ok = parse_int(argv[i + 1]);
            if ok { frames = n; }
        } else if argv[i] == "--out" {
            out.append(argv[i + 1]);
        }
        i += 2;
    }
    guard gfx::open("gfx2d showcase", W, H) else {
        print("gfx: ", gfx::error());
        return;
    }
    let grain = gfx::texture2d(64, 64);
    var data: u8[>..] = [];
    for y in 64 {
        for x in 64 {
            let v = (190 + 65 * sin(x * 0.4 + sin(y * 0.15) * 3.0)) as u8;
            data.append([v, v, v, 255]);
        }
    }
    gfx::update_texture(grain, data);
    // The pixel canvas's scene: drawn into a target of its own first, then
    // the showcase's frame takes it as an image.
    let pixels = gfx::render_target(320, 180, gfx::RGBA8);

    var drawn = 0;
    while gfx::frame() {
        if drawn == frames { break; }
        // A fixed time, so every run draws the same frames.
        let t: f64 = drawn / 60.0;
        gfx2d::draw_into(pixels, gfx2d::BLACK) {
            gfx2d::pixel_canvas(80, 45, gfx2d::rgb(0x1D2B53)) {
                gfx2d::rect(4, 30, 72, 11, gfx2d::rgb(0x008751));
                gfx2d::circle(20 + (drawn % 40), 22, 6, gfx2d::rgb(0xFF77A8));
                gfx2d::rect(60, 10, 8, 20, gfx2d::rgb(0x5F574F));
            };
        };
        gfx2d::frame(gfx2d::rgb(0xF2E9E4), 4) {
            scene(t, grain);
            gfx2d::image(pixels, gfx2d::rect_of(20, 520, 320, 180), gfx2d::WHITE, gfx2d::FILTER_NEAREST);
        };
        drawn++;
    }
    // Checks on the last frame, read back.
    let px = gfx::read_pixels(gfx::screen());
    fn pixel(x: i64, y: i64) -> int4 {
        let k = (y * W + x) * 4;
        int4 { px[k], px[k + 1], px[k + 2], px[k + 3] }
    }
    fn near(a: int4, b: int4) -> bool {
        abs(a.x - b.x) <= 3 && abs(a.y - b.y) <= 3 && abs(a.z - b.z) <= 3
    }
    let accent = gfx2d::palette(8, 0.15);
    fn bytes(c: gfx2d::Color) -> int4 {
        let v = gfx2d::to_u32(c);
        int4 { ((v >> 16) & 255) as i32, ((v >> 8) & 255) as i32, (v & 255) as i32, 255 }
    }
    check("a rect's color", near(pixel(70, 50), bytes(accent[0])));
    check("the background", near(pixel(1270, 710), bytes(gfx2d::rgb(0xF2E9E4))));
    check("an even-odd hole", near(pixel(780, 150), bytes(gfx2d::rgb(0xF2E9E4))));
    check("a nonzero middle", near(pixel(680, 150), bytes(accent[6])));
    check("clipped outside", near(pixel(150, 420 - 70), bytes(gfx2d::rgb(0xF2E9E4))));
    check("screen-blended red", pixel(400, 420).x > 240);
    check("a card's white", near(pixel(600, 460), int4 { 255, 255, 255, 255 }));
    check("the pixel canvas's ground", near(pixel(100, 680), bytes(gfx2d::rgb(0x008751))));
    if out.len > 0 {
        let path = str(out, "/gfx2d_showcase.png");
        check("screenshot saved", gfx::screenshot(path));
    }
    print("checks: ", failed, " failed");
    gfx::close();
}
