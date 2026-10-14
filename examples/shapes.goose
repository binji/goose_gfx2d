// gfx2d's shapes, outlines, transforms and colors in one animated scene.
//
//   goose examples/shapes.goose
//   goose examples/shapes.goose -- --frames 60 --screenshot shapes.png
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
    guard gfx::open("gfx2d: shapes", 800, 600, gfx::WINDOW_RESIZABLE) else {
        write_stderr(str("gfx: ", gfx::error(), "\n"));
        return;
    }
    let colors = gfx2d::palette(12, 0.1);
    var drawn = 0;
    while gfx::frame() {
        if gfx::key_pressed("Escape") || drawn == frames { break; }
        let t: f32 = drawn / 60.0;
        let size = gfx::screen_size();
        let w: f32 = size.x;
        let h: f32 = size.y;
        let ink = gfx2d::rgb(0x2B2D42);

        gfx2d::frame(gfx2d::rgb(0xF4F1EA)) {
            // A row of filled shapes, and their outlines under them.
            gfx2d::rect(40, 40, 120, 80, colors[0]);
            gfx2d::rounded_rect(190, 40, 120, 80, 20, colors[1]);
            gfx2d::rounded_rect(340, 40, 120, 80, float4 { 40, 0, 40, 0 }, colors[2]);
            gfx2d::circle(550, 80, 40, colors[3]);
            gfx2d::ellipse(690, 80, 70, 40, colors[4]);
            gfx2d::rect_outline(40, 150, 120, 80, 3, ink);
            gfx2d::rounded_rect_outline(190, 150, 120, 80, 20, 3, ink);
            gfx2d::circle_outline(550, 190, 40, 1, ink);
            gfx2d::ellipse_outline(690, 190, 70, 40, 6, gfx2d::fade(ink, 0.5));
            gfx2d::ring(400, 190, 22, 40, gfx2d::mix(colors[5], colors[6], 0.5));

            // Pies and arcs: a clock-like gauge, sweeping.
            let sweep = (t * 0.8) % TAU;
            gfx2d::pie(120, 360, 70, -PI / 2, -PI / 2 + sweep, colors[7]);
            gfx2d::pie_outline(120, 360, 70, -PI / 2, -PI / 2 + sweep, 2, ink);
            gfx2d::arc(300, 360, 60, PI * 0.75, PI * 2.25, 14, gfx2d::rgb(0xDDDDDD), gfx2d::CAP_ROUND);
            gfx2d::arc(300, 360, 60, PI * 0.75, PI * 0.75 + (sin(t) * 0.5 + 0.5) * PI * 1.5, 14,
                       colors[8], gfx2d::CAP_ROUND);

            // Lines of every cap, and hairlines that stay a pixel wide.
            for k in 3 {
                let y: f32 = 300 + k * 30;
                gfx2d::line(420, y, 560, y, 14, colors[9 + k], k);
                gfx2d::line(420, y, 560, y, 1, ink);
            }
            for k in 20 {
                gfx2d::line(600, 300, 600 + 150 * cos(k * 0.08), 300 + 150 * sin(k * 0.08),
                            0.25 + k * 0.1, ink);
            }

            // A pinwheel of rotated, scaled squares under the current transform.
            gfx2d::translate(w * 0.5, h - 110) {
                gfx2d::rotate(t * 0.5) {
                    for k in 12 {
                        gfx2d::rotate(k * TAU / 12) {
                            gfx2d::scale(1 + 0.3 * sin(t * 2 + k)) {
                                gfx2d::rounded_rect(40, -10, 50, 20, 6,
                                                    gfx2d::hsv(k / 12.0, 0.6, 0.9));
                            };
                        };
                    }
                };
                gfx2d::circle(0, 0, 30, ink);
                gfx2d::circle(0, 0, 24, gfx2d::lighten(ink, 0.3));
            };
        };
        drawn++;
    }
    if screenshot.len > 0 { gfx::screenshot(screenshot); }
    gfx::close();
}
