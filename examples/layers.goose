// gfx2d's clips and layers: shapes clipped by rounded rects, circles and a
// path; a card with a drop shadow; group opacity; blend modes; a blur; and
// box shadows.
//
//   goose examples/layers.goose
//   goose examples/layers.goose -- --frames 60 --screenshot layers.png
//
// Escape or closing the window quits.
import std;
import vec;
import math;
import os;
import gfx;
import gfx2d from "..";

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
    guard gfx::open("gfx2d: clips and layers", 800, 600, gfx::WINDOW_RESIZABLE) else {
        write_stderr(str("gfx: ", gfx::error(), "\n"));
        return;
    }
    let ink = gfx2d::rgb(0x22223B);
    let colors = gfx2d::palette(6, 0.6);
    let modes = [gfx2d::BLEND_NORMAL, gfx2d::BLEND_MULTIPLY, gfx2d::BLEND_SCREEN, gfx2d::BLEND_OVERLAY,
                 gfx2d::BLEND_DIFFERENCE, gfx2d::BLEND_ERASE];
    let names = ["normal", "multiply", "screen", "overlay", "difference", "erase"];
    var drawn = 0;
    while gfx::frame() {
        if gfx::key_pressed("Escape") || drawn == frames { break; }
        let t: f64 = drawn / 60.0;
        gfx2d::frame(gfx2d::rgb(0xEDE7E3), 4) {
            // Stripes clipped by a rounded rect, a circle, and a star path,
            // turning.
            fn stripes(x: f64, y: f64) {
                for k in 12 {
                    gfx2d::rect(x - 80 + k * 14, y - 80, 7, 160, colors[k % 6]);
                }
            }
            gfx2d::clip_rounded_rect(30, 30, 140, 120, 24) { stripes(100, 90); };
            gfx2d::clip_circle(270, 90, 60) { stripes(270, 90); };
            var star = gfx2d::Path {};
            gfx2d::star(star, 0, 0, 5, 70, 30, t * 0.5);
            gfx2d::translate(440, 90) { gfx2d::clip_path(star) { stripes(0, 0); }; };

            // A card: a drop shadow from a layer, its content clipped to it.
            gfx2d::layer(gfx2d::LayerDesc { shadow: gfx2d::rgba(0x000000, 0.35),
                                            shadow_offset: float2 { 6, 10 }, shadow_blur: 8 }) {
                gfx2d::rounded_rect(560, 30, 200, 130, 16, gfx2d::WHITE);
                gfx2d::clip_rounded_rect(560, 30, 200, 130, 16) {
                    gfx2d::rect(560, 30, 200, 50, gfx2d::linear(560, 0, 760, 0, colors[0], colors[3]));
                };
                gfx2d::text(576, 96, "A card", 22, ink);
                gfx2d::text(576, 126, "drop shadow, clipped header", 13, gfx2d::fade(ink, 0.7));
            };

            // Group opacity: three circles at half opacity, apart and as
            // one layer.
            for k in 3 { gfx2d::circle(70 + k * 40, 260, 45, gfx2d::fade(colors[k], 0.5)); }
            gfx2d::layer(0.5) {
                for k in 3 { gfx2d::circle(270 + k * 40, 260, 45, colors[k]); }
            };
            gfx2d::text(50, 315, "each at 0.5", 13, ink);
            gfx2d::text(250, 315, "a layer at 0.5", 13, ink);

            // Blend modes: a disc over a gradient, in each.
            for m, k in modes {
                let x = 40.0 + k * 125;
                gfx2d::rounded_rect(x, 350, 110, 90, 10,
                                    gfx2d::linear(x, 0, x + 110, 0, gfx2d::rgb(0x003049), gfx2d::rgb(0xFCBF49)));
                gfx2d::layer(gfx2d::LayerDesc { blend: m as i32 }) {
                    gfx2d::circle(x + 55 + 20 * sin(t + k), 395, 35, gfx2d::rgb(0xD62828));
                };
                gfx2d::text(x + 55, 448, names[k], gfx2d::TextStyle { size: 13, align: gfx2d::ALIGN_CENTER }, ink);
            }

            // A blur, pulsing; and box shadows of three softnesses.
            gfx2d::layer(gfx2d::LayerDesc { blur: (3 + 3 * sin(t * 2)) as f32 }) {
                gfx2d::text(480, 270, "blurred", 40, ink);
            };
            for k in 3 {
                let x = 60.0 + k * 150;
                gfx2d::box_shadow(x, 500 + 4, 110, 60, 12, 4 + k * 12, gfx2d::rgba(0x000000, 0.5));
                gfx2d::rounded_rect(x, 500, 110, 60, 12, gfx2d::WHITE);
            }
        };
        drawn++;
    }
    if screenshot.len > 0 { gfx::screenshot(screenshot); }
    gfx::close();
}
