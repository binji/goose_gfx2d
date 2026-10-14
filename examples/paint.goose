// gfx2d's paints: gradients of each kind, a gradient blended with a
// texture, additive glows, a nine-slice panel and sprites. The textures are
// made here, so the example needs no files.
//
//   goose examples/paint.goose
//   goose examples/paint.goose -- --frames 60 --screenshot paint.png
//
// Escape or closing the window quits.
import std;
import vec;
import math;
import os;
import gfx;
import gfx2d from "..";

// A texture of w x h from a function giving each pixel's color.
fn make_texture<F>(w: i64, h: i64) -> gfx::Texture {
    var data: u8[>..] = [];
    for y in h {
        for x in w {
            let c: gfx2d::Color = F(x, y);
            let v = gfx2d::to_u32(c);
            data.append([((v >> 16) & 255) as u8, ((v >> 8) & 255) as u8, (v & 255) as u8,
                         (v >> 24) as u8]);
        }
    }
    let t = gfx::texture2d(w, h);
    gfx::update_texture(t, data);
    t
}

fn main() {
    var frames = -1;
    var screenshot: u8[>..] = [];
    let argv = args();
    var i = 1;
    while i + 1 < argv.len {
        if argv[i] == "--frames" {
            let n, ok = parse_int(argv[i + 1]);
            if ok { frames = n; }
        } else if argv[i] == "--screenshot" {
            screenshot.append(argv[i + 1]);
        }
        i += 2;
    }
    guard gfx::open("gfx2d: paint", 800, 600, gfx::WINDOW_RESIZABLE) else {
        write_stderr(str("gfx: ", gfx::error(), "\n"));
        return;
    }

    // Wood-ish stripes, gray, to be multiplied with a gradient.
    let grain = make_texture(64, 64) { x, y =>
        let v = 0.75 + 0.25 * sin(x * 0.4 + sin(y * 0.15) * 3.0);
        gfx2d::gray(v)
    };
    // A rounded panel frame for nine-slicing: 24x24, an 8-pixel border.
    let panel = make_texture(24, 24) { x, y =>
        let dx = max(max(7.5 - x, x - 16.5), 0.0);
        let dy = max(max(7.5 - y, y - 16.5), 0.0);
        let d = sqrt(dx * dx + dy * dy);
        if d > 7.5 { gfx2d::TRANSPARENT }
        else if d > 5.5 { gfx2d::rgb(0x3D5A80) }
        else { gfx2d::rgba(0xE0FBFC, 0.92) }
    };
    // Four 8x8 sprites side by side: a ball in four colors.
    let sheet = make_texture(32, 8) { x, y =>
        let cx = (x % 8) - 3.5;
        let cy = y - 3.5;
        let inside = cx * cx + cy * cy < 13.0;
        let hues: f64[4] = [0.0, 0.15, 0.4, 0.6];
        if inside { gfx2d::hsv(hues[x / 8], 0.7, 1.0) } else { gfx2d::TRANSPARENT }
    };

    let ink = gfx2d::rgb(0x293241);
    var drawn = 0;
    while gfx::frame() {
        if gfx::key_pressed("Escape") || drawn == frames { break; }
        let t: f64 = drawn / 60.0;

        gfx2d::frame(gfx2d::rgb(0x1B1F2A)) {
            // A screen-wide background gradient, pinned to the screen.
            let size = gfx::screen_size();
            var sky = gfx2d::linear(0, 0, 0, size.y, gfx2d::rgb(0x1B1F2A), gfx2d::rgb(0x3D2C4E));
            sky.space = gfx2d::SPACE_SCREEN;
            gfx2d::rect(0, 0, size.x, size.y, sky);

            // Linear gradients in three color spaces: sRGB dips dark and gray
            // between complements, OKLab does not.
            let stops = [gfx2d::stop(0, gfx2d::rgb(0xFF2D55)), gfx2d::stop(1, gfx2d::rgb(0x00C2FF))];
            for space in 3 {
                var g = gfx2d::linear_gradient(40, 0, 340, 0, stops);
                g.space = space as i32;
                gfx2d::rounded_rect(40, 40 + space * 50, 300, 36, 8, gfx2d::paint(g));
            }

            // The brief's hard case: a gradient blended with a texture.
            gfx2d::rounded_rect(380, 40, 380, 136, 18, gfx2d::Paint {
                gradient: gfx2d::linear_gradient(380, 40, 760, 176, [
                    gfx2d::stop(0, gfx2d::rgb(0xFF8800)), gfx2d::stop(0.6, gfx2d::rgb(0xCC2266)),
                    gfx2d::stop(1, gfx2d::rgb(0x2200AA))]),
                image: gfx2d::image_pattern(grain, gfx2d::mul(gfx2d::translation(380, 40),
                                                              gfx2d::rotation(0.3))),
                image_mode: gfx2d::IMAGE_MULTIPLY,
            });

            // A conic color wheel, turning, and a radial highlight off center.
            var wheel: gfx2d::Stop[>..] = [];
            for k in 7 { wheel.push(gfx2d::stop(k / 6.0, gfx2d::hsv(k / 6.0, 0.85, 1.0))); }
            gfx2d::circle(120, 310, 80, gfx2d::paint(gfx2d::conic_gradient(120, 310, t, wheel)));
            gfx2d::circle(120, 310, 30, gfx2d::rgb(0x1B1F2A));
            gfx2d::circle(300, 310, 80, gfx2d::paint(gfx2d::radial_gradient(300, 310, 80, 270, 280, [
                gfx2d::stop(0, gfx2d::WHITE), gfx2d::stop(0.3, gfx2d::rgb(0x7FDBFF)),
                gfx2d::stop(1, gfx2d::rgb(0x0B3D91))])));

            // Additive glows: radial gradients to transparent, added up.
            for k in 5 {
                let a = t * 0.7 + k * TAU / 5;
                let x = 520 + cos(a) * 60;
                let y = 310 + sin(a) * 60;
                let c = gfx2d::hsv(k / 5.0, 0.8, 1.0);
                gfx2d::circle(x, y, 70, gfx2d::with_blend(
                    gfx2d::radial(x, y, 70, c, gfx2d::with_alpha(c, 0)), gfx2d::BLEND_ADD));
            }

            // A repeating stripe pattern, by a gradient's spread.
            var stripes = gfx2d::linear_gradient(640, 230, 652, 242, [
                gfx2d::stop(0, ink), gfx2d::stop(0.5, ink), gfx2d::stop(0.5, gfx2d::rgb(0xEE6C4D)),
                gfx2d::stop(1, gfx2d::rgb(0xEE6C4D))]);
            stripes.spread = gfx2d::SPREAD_REPEAT;
            gfx2d::rounded_rect(640, 230, 120, 160, 12, gfx2d::paint(stripes));

            // A nine-slice panel, stretched with the time, and sprites on it.
            let w = 300 + 80 * sin(t);
            gfx2d::nine_slice(panel, gfx2d::rect_of(40, 420, w, 140), float4 { 8, 8, 8, 8 });
            for k in 4 {
                let bob = 6 * sin(t * 3 + k);
                gfx2d::image(sheet, gfx2d::rect_of(70 + k * 60, 460 + bob, 40, 40),
                             gfx2d::rect_of(k * 8, 0, 8, 8), gfx2d::WHITE, gfx2d::FILTER_NEAREST);
            }
            // The grain texture alone, tinted, and turning.
            gfx2d::translate(560, 490) {
                gfx2d::rotate(t * 0.3) {
                    gfx2d::image(grain, gfx2d::rect_of(-64, -64, 128, 128), gfx2d::rgb(0xC08552));
                };
            };
        };
        drawn++;
    }
    if screenshot.len > 0 { gfx::screenshot(screenshot); }
    gfx::close();
}
