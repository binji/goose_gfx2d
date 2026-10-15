// The Goose logo, from its SVG: the paths' data parsed by svg_path, the
// goose's speed lines rippling and its head bobbing by warping the path a
// little every frame, and now and then a rainbow shine sweeping across it,
// with a glow.
//
// goose_logo.svg is the Goose repository's vscode/fileicons/goose-light-icon.svg
// (a potrace trace, Apache License 2.0, as Goose).
//
//   goose examples/goose_logo.goose
//   goose examples/goose_logo.goose -- --frames 90 --screenshot goose_logo.png
//
// Escape or closing the window quits.
import std;
import vec;
import math;
import os;
import gfx;
import gfx2d from "..";

// The logo, from the SVG file's <path d="..."> elements, in the SVG's
// viewBox: its group's transform (translate(0, 768) scale(0.1, -0.1)), which
// potrace writes, is applied here rather than parsed.
fn load_logo(svg: const u8[:], logo: gfx2d::Path&) {
    var i = 0;
    while i + 3 < svg.len {
        if svg[i] == ' ' && svg[i + 1] == 'd' && svg[i + 2] == '=' && svg[i + 3] == '"' {
            var j = i + 4;
            while j < svg.len && svg[j] != '"' { j++; }
            if !gfx2d::svg_path(logo, svg[i + 4..j]) { abort("goose_logo: path data it cannot read"); }
            i = j;
        }
        i++;
    }
    gfx2d::transform(logo, gfx2d::Affine { 0.1, 0.0, 0.0, -0.1, 0.0, 768.0 });
}

fn smoothstep(x: f64) -> f64 {
    let t = clamp(x, 0.0, 1.0);
    t * t * (3 - 2 * t)
}

// The logo moved a little at time t: the speed lines, toward its tail (x
// from about 650 to 1615), in a wave running back along them; the head (x
// under about 420) bobbing.
fn animate(logo: gfx2d::Path&, t: f64) {
    gfx2d::warp(logo) { q =>
        let x: f64 = q.x;
        let tail = smoothstep((x - 650) / 600);
        let head = 1 - smoothstep((x - 250) / 200);
        let dy = 9 * tail * sin(x * 0.018 - t * 6) + 6 * head * sin(t * 2.4);
        let dx = 3 * head * sin(t * 2.4 + 0.8);
        q + float2 { dx as f32, dy as f32 }
    };
}

let SHINE_EVERY = 4.0;      // seconds
let SHINE_FOR = 1.3;

// The rainbow band across the logo at u, from 0 (before its left end) to 1
// (past its right): a gradient across the band, transparent at its edges,
// in OKLab so the colors between stay bright.
fn rainbow(u: f64) -> gfx2d::Paint {
    let c = -300 + u * 2300;
    let d = float2 { 0.89, 0.45 };      // across the band, which leans
    let w = 230.0;
    var stops: gfx2d::Stop[>..] = [];
    stops.push(gfx2d::stop(0.0, gfx2d::with_alpha(gfx2d::hsv(0.0, 0.85, 1.0), 0)));
    for k in 7 { stops.push(gfx2d::stop(0.15 + k * 0.7 / 6, gfx2d::hsv(k / 7.0, 0.85, 1.0))); }
    stops.push(gfx2d::stop(1.0, gfx2d::with_alpha(gfx2d::hsv(6 / 7.0, 0.85, 1.0), 0)));
    var g = gfx2d::linear_gradient(c - d.x * w, 384 - d.y * w, c + d.x * w, 384 + d.y * w, stops);
    g.space = gfx2d::INTERPOLATE_OKLAB;
    gfx2d::paint(g)
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
    guard gfx::open("gfx2d: the Goose logo", 960, 540, gfx::WINDOW_RESIZABLE) else {
        write_stderr(str("gfx: ", gfx::error(), "\n"));
        return;
    }
    var logo = gfx2d::Path {};
    load_logo(embed_file("goose_logo.svg"), logo);
    let bounds = gfx2d::bounds(logo);

    var drawn = 0;
    while gfx::frame() {
        if gfx::key_pressed("Escape") || drawn == frames { break; }
        // Seconds since the start; frame by frame when the frames are
        // counted, so a screenshot is the same each run.
        let t: f64 = if frames >= 0 { drawn / 60.0 } else { gfx::time() };
        var moving = copy(logo);
        animate(moving, t);
        let since = (t + SHINE_EVERY - 1.0) % SHINE_EVERY;     // the first shine at 1s
        let shining = since < SHINE_FOR;
        let u = since / SHINE_FOR;
        let strength = sin(u * PI);

        let size = gfx::screen_size();
        let fit = gfx2d::fit(bounds, gfx2d::rect_of(60, 60, size.x - 120, size.y - 120), gfx2d::FIT_CONTAIN);
        gfx2d::frame(gfx2d::rgb(0x101018)) {
            gfx2d::rect(0, 0, size.x, size.y, gfx2d::radial(size.x / 2, size.y / 2, size.x * 0.6,
                                                            gfx2d::rgb(0x23233A), gfx2d::rgb(0x101018)));
            gfx2d::transform(fit) {
                // The goose, with a soft shadow below it.
                gfx2d::layer(gfx2d::LayerDesc { shadow: gfx2d::rgba(0x000000, 0.6),
                                                shadow_offset: float2 { 0, 10 }, shadow_blur: 12 }) {
                    gfx2d::fill(moving, gfx2d::rgb(0xF5F1E8));
                };
                if shining {
                    // The band on the goose, and a glow of it, blurred and
                    // added, spilling past its edges.
                    let band = gfx2d::with_opacity(rainbow(u), strength);
                    gfx2d::fill(moving, band);
                    gfx2d::layer(gfx2d::LayerDesc { opacity: (0.8 * strength) as f32,
                                                    blend: gfx2d::BLEND_ADD as i32, blur: 10 }) {
                        gfx2d::fill(moving, rainbow(u));
                    };
                }
            };
        };
        drawn++;
    }
    if screenshot.len > 0 { gfx::screenshot(screenshot); }
    gfx::close();
}
