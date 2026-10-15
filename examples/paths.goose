// gfx2d's paths: Bézier curves, fill rules, strokes with every join and
// cap, dashes, polylines as a chart, and paints on paths.
//
//   goose examples/paths.goose
//   goose examples/paths.goose -- --frames 60 --screenshot paths.png
//
// Escape or closing the window quits.
import std;
import vec;
import math;
import os;
import gfx;
import gfx2d from "..";

fn heart(p: gfx2d::Path&, cx: f64, cy: f64, s: f64) {
    gfx2d::move_to(p, cx, cy + 0.35 * s);
    gfx2d::cubic_to(p, cx - 0.1 * s, cy + 0.25 * s, cx - 0.5 * s, cy + 0.05 * s, cx - 0.5 * s, cy - 0.15 * s);
    gfx2d::cubic_to(p, cx - 0.5 * s, cy - 0.45 * s, cx - 0.1 * s, cy - 0.5 * s, cx, cy - 0.25 * s);
    gfx2d::cubic_to(p, cx + 0.1 * s, cy - 0.5 * s, cx + 0.5 * s, cy - 0.45 * s, cx + 0.5 * s, cy - 0.15 * s);
    gfx2d::cubic_to(p, cx + 0.5 * s, cy + 0.05 * s, cx + 0.1 * s, cy + 0.25 * s, cx, cy + 0.35 * s);
    gfx2d::close(p);
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
    guard gfx::open("gfx2d: paths", 800, 600, gfx::WINDOW_RESIZABLE) else {
        write_stderr(str("gfx: ", gfx::error(), "\n"));
        return;
    }
    let ink = gfx2d::rgb(0x22223B);
    let paper = gfx2d::rgb(0xF2E9E4);
    let accents = gfx2d::palette(6, 0.05);

    // A data series for the chart.
    var series: float2[>..] = [];
    for k in 40 {
        let x: f64 = k;
        series.push(float2 { (440 + x * 8.5) as f32,
                             (520 - 60 - 40 * sin(x * 0.35) - 20 * sin(x * 1.3)) as f32 });
    }

    var drawn = 0;
    while gfx::frame() {
        if gfx::key_pressed("Escape") || drawn == frames { break; }
        let t: f64 = drawn / 60.0;

        gfx2d::frame(paper) {
            // A heart of cubics, with a radial gradient, beating, outlined.
            var h = gfx2d::Path {};
            heart(h, 120, 130, 180 + 10 * sin(t * 6));
            gfx2d::fill(h, gfx2d::radial(100, 100, 120, gfx2d::rgb(0xFF8FA3), gfx2d::rgb(0xC9184A)));
            gfx2d::stroke(h, 3, ink);

            // The same pentagram by each fill rule.
            var star = gfx2d::Path {};
            for k in 5 {
                let a = -PI / 2 + k * 2 * TAU / 5;
                if k == 0 { gfx2d::move_to(star, 300 + 70 * cos(a), 130 + 70 * sin(a)); }
                else { gfx2d::line_to(star, 300 + 70 * cos(a), 130 + 70 * sin(a)); }
            }
            gfx2d::close(star);
            gfx2d::fill(star, accents[0]);
            gfx2d::translate(160, 0) { gfx2d::fill(star, accents[1], gfx2d::EVEN_ODD); };
            gfx2d::stroke(star, gfx2d::Stroke { width: 1, pixels: true }, ink);

            // A ring with a hole, by even-odd, turning, its edge dashed.
            gfx2d::translate(660, 130) {
                gfx2d::rotate(t * 0.4) {
                    var ring = gfx2d::Path {};
                    gfx2d::rounded_rect(ring, -80, -80, 160, 160, 30);
                    gfx2d::circle(ring, 0, 0, 45);
                    gfx2d::fill(ring, accents[2], gfx2d::EVEN_ODD);
                    gfx2d::stroke(ring, gfx2d::Stroke { width: 3, cap: gfx2d::CAP_ROUND,
                                                        dash: [12, 8], dash_offset: t * 40 }, ink);
                };
            };

            // Joins and caps: miter, round and bevel, on a zigzag, and a
            // translucent one crossing itself (drawn once where it crosses).
            for k in 3 {
                let x = 40.0 + k * 130;
                let zig = [float2 { x as f32, 330 }, float2 { (x + 30) as f32, 270 },
                           float2 { (x + 60) as f32, 330 }, float2 { (x + 90) as f32, 270 }];
                gfx2d::polyline(zig, 16, accents[3 + k], k, k);
                gfx2d::polyline(zig, 1, ink);
            }
            var loop_path = gfx2d::Path {};
            gfx2d::move_to(loop_path, 450, 330);
            gfx2d::cubic_to(loop_path, 900, 170, 330, 170, 760, 330);
            gfx2d::stroke(loop_path, gfx2d::Stroke { width: 22, cap: gfx2d::CAP_ROUND },
                          gfx2d::rgba(0x4A4E69, 0.5));

            // A chart: a filled area under a polyline, and its points.
            var area = gfx2d::Path {};
            gfx2d::polygon(area, series, false);
            gfx2d::line_to(area, series[series.len - 1].x, 520);
            gfx2d::line_to(area, series[0].x, 520);
            gfx2d::close(area);
            gfx2d::fill(area, gfx2d::linear(0, 400, 0, 520, gfx2d::with_alpha(accents[2], 0.6),
                                            gfx2d::with_alpha(accents[2], 0.0)));
            gfx2d::polyline(series, 2.5, accents[2], gfx2d::CAP_ROUND, gfx2d::JOIN_ROUND);
            for q in series { gfx2d::circle(q, 3, ink); }
            gfx2d::line(440, 520, 780, 520, 1, ink);

            // Regular polygons and stars, turning.
            for k in 4 {
                gfx2d::translate(80 + k * 90, 470) {
                    gfx2d::rotate(t * (k + 1) * 0.3) {
                        if k % 2 == 0 { gfx2d::regular_polygon(0, 0, 35, k + 3, accents[k]); }
                        else { gfx2d::star(0, 0, k + 4, 38, 16, accents[k]); }
                    };
                };
            }
        };
        drawn++;
    }
    if screenshot.len > 0 { gfx::screenshot(screenshot); }
    gfx::close();
}
