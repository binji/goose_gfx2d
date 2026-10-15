// The Goose logo, from its SVG: the paths' data parsed by svg_path, the
// goose's speed lines rippling and its head bobbing by warping the path a
// little every frame, its name centered below it, and now and then a gloss
// like iridescent metal sweeping across both, with a glow.
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
let SHINE_FOR = 0.9;

// The gloss at u, from 0 (before the left of the span x0 to x1) to 1 (past
// its right), in the window's pixels (SPACE_SCREEN), so one paint crosses
// the logo, under its transform, and the text alike: a narrow white
// highlight, with a film's thin tints either side (violet and teal ahead,
// gold and pink behind), fading out at the band's edges, mixed in OKLab so
// the tints stay clean.
fn gloss(u: f64, x0: f64, x1: f64, y: f64) -> gfx2d::Paint {
    let w = (x1 - x0) * 0.16;            // half the band's width
    let c = x0 - w * 2 + u * (x1 - x0 + w * 4);
    let d = float2 { 0.89, 0.45 };      // across the band, which leans
    var g = gfx2d::linear_gradient(c - d.x * w, y - d.y * w, c + d.x * w, y + d.y * w, [
        gfx2d::stop(0.00, gfx2d::rgba(0x7A6CFF, 0.0)),
        gfx2d::stop(0.22, gfx2d::rgba(0x7A6CFF, 0.30)),
        gfx2d::stop(0.36, gfx2d::rgba(0x3FD5D0, 0.45)),
        gfx2d::stop(0.47, gfx2d::rgba(0xFFFFFF, 0.95)),
        gfx2d::stop(0.53, gfx2d::rgba(0xFFFFFF, 0.95)),
        gfx2d::stop(0.64, gfx2d::rgba(0xF5C77A, 0.45)),
        gfx2d::stop(0.78, gfx2d::rgba(0xFF7FC8, 0.30)),
        gfx2d::stop(1.00, gfx2d::rgba(0xFF7FC8, 0.0)),
    ]);
    g.space = gfx2d::INTERPOLATE_OKLAB;
    var p = gfx2d::paint(g);
    p.space = gfx2d::SPACE_SCREEN;
    p
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
        // The logo above, its name below: the name's size follows the
        // window's, and the logo fits what is left.
        let name_size = size.y * 0.13;
        let fit = gfx2d::fit(bounds, gfx2d::rect_of(60, 40, size.x - 120, size.y - 80 - name_size * 1.4),
                             gfx2d::FIT_CONTAIN);
        let placed = gfx2d::transformed_bounds(fit, bounds);
        let cream = gfx2d::rgb(0xF5F1E8);
        let name_style = gfx2d::TextStyle { size: name_size as f32, align: gfx2d::ALIGN_CENTER };
        let name_y = placed.y + placed.h + name_size * 0.15;
        let shine = gloss(u, placed.x, placed.x + placed.w, size.y * 0.5);
        gfx2d::frame(gfx2d::rgb(0x101018)) {
            gfx2d::rect(0, 0, size.x, size.y, gfx2d::radial(size.x / 2, size.y / 2, size.x * 0.6,
                                                            gfx2d::rgb(0x23233A), gfx2d::rgb(0x101018)));
            // The goose, with a soft shadow below it, and its name.
            gfx2d::layer(gfx2d::LayerDesc { shadow: gfx2d::rgba(0x000000, 0.6),
                                            shadow_offset: float2 { 0, 10 }, shadow_blur: 12 }) {
                gfx2d::transform(fit) { gfx2d::fill(moving, cream); };
                gfx2d::text(size.x / 2, name_y, "Goose", name_style, cream);
            };
            if shining {
                // The gloss on both, and a glow of it, blurred and added,
                // spilling past their edges.
                let band = gfx2d::with_opacity(shine, strength);
                gfx2d::transform(fit) { gfx2d::fill(moving, band); };
                gfx2d::text(size.x / 2, name_y, "Goose", name_style, band);
                gfx2d::layer(gfx2d::LayerDesc { opacity: (0.6 * strength) as f32,
                                                blend: gfx2d::BLEND_ADD, blur: 8 }) {
                    gfx2d::transform(fit) { gfx2d::fill(moving, shine); };
                    gfx2d::text(size.x / 2, name_y, "Goose", name_style, shine);
                };
            }
        };
        drawn++;
    }
    if screenshot.len > 0 { gfx::screenshot(screenshot); }
    gfx::close();
}
