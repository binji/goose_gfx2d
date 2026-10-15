// gfx2d's benchmarks: a representative case for each kind of drawing,
// timed frame by frame into a 1920x1080 target, headless. bench/README.md
// says what each case is for; bench/run_bench.py builds this, runs it and
// writes bench/results.md.
//
//   goose bench/bench.goose                       every case
//   goose bench/bench.goose -- circles text_page  the cases whose names contain these
//   goose bench/bench.goose -- --frames 20 --list
//
// Each frame is timed in three parts, on the monotonic clock:
//
//   record  the draw calls, begin() to just before end(): building
//           instances, paints, gradient ramps, tessellating paths, laying
//           out text and rasterizing new glyphs, all on the CPU
//   end     end(): uploading buffers, ramps and glyphs, and recording the
//           pass's draws, also on the CPU
//   gpu     gfx::flush(): submitting the frame and waiting until the GPU
//           has drawn it
//
// Each case runs WARMUP frames untimed, then --frames timed ones (default
// 60), and reports each part's median in milliseconds, with what the last
// frame drew. Every frame draws the same thing, from the same seeds: what
// varies between frames is the timing only.
//
// Output lines are `case <name> <frames> <record> <end> <gpu> <instances>
// <triangles> <draws> <bytes uploaded> <passes>`, for run_bench.py.

import std;
import vec;
import math;
import os;
import gfx;
import gfx2d from "..";

let W = 1920;
let H = 1080;
let WARMUP = 5;

var target: gfx::Texture;

// A small deterministic generator (xorshift64*), so every run draws the same.
var rng_state: u64 = 1;
fn seed(s: u64) { rng_state = s * 0x9E3779B97F4A7C15 + 1; }
fn rand() -> f64 {
    rng_state ^= rng_state >> 12;
    rng_state ^= rng_state << 25;
    rng_state ^= rng_state >> 27;
    ((rng_state * 0x2545F4914F6CDD1D) >> 11) / 9007199254740992.0
}
fn rand(lo: f64, hi: f64) -> f64 { lo + (hi - lo) * rand() }
fn rand_color() -> gfx2d::Color { gfx2d::hsv(rand(), rand(0.4, 0.9), rand(0.5, 1.0)) }

fn median(xs: f64[>..]&) -> f64 {
    sort(xs);
    if xs.len == 0 { return 0.0; }
    xs[xs.len / 2]
}

fn ms(x: f64) -> u8[>..] {
    let v = round(x * 1000) / 1000;
    str(v)
}

var selected: u8[][>..] = [];
var frames = 60;
var listing = false;

fn wanted(name: const u8[:]) -> bool {
    if selected.len == 0 { return true; }
    for s in selected {
        if s.len <= name.len {
            for i in 0..name.len - s.len + 1 {
                if name[i..i + s.len] == s { return true; }
            }
        }
    }
    false
}

// Times the case: F(frame) draws one frame's content, multisampled
// `samples` times if more than 1.
fn run<F>(name: const u8[:], samples: i64 = 1) {
    if listing { print(name); return; }
    guard wanted(name);
    var record: f64[>..] = [];
    var end: f64[>..] = [];
    var gpu: f64[>..] = [];
    for i in WARMUP + frames {
        let t0 = clock_ns();
        gfx2d::begin(target, gfx2d::WHITE, samples);
        F(i);
        let t1 = clock_ns();
        gfx2d::end();
        let t2 = clock_ns();
        gfx::flush();
        let t3 = clock_ns();
        if i >= WARMUP {
            record.push((t1 - t0) / 1000000.0);
            end.push((t2 - t1) / 1000000.0);
            gpu.push((t3 - t2) / 1000000.0);
        }
    }
    let s = gfx2d::stats();
    let r = median(record);
    let e = median(end);
    let g = median(gpu);
    print("case ", name, " ", frames, " ", ms(r), " ", ms(e), " ", ms(g), " ", s.instances, " ",
          s.triangles, " ", s.draws, " ", s.bytes, " ", s.passes);
}

// --- shapes ------------------------------------------------------------------------

// Nothing but the frame: clearing the target, submitting, waiting. What
// every other case's numbers include.
fn empty() {}

fn circles() {
    seed(1);
    for i in 10000 { gfx2d::circle(rand(0, W), rand(0, H), rand(2, 20), rand_color()); }
}

fn mixed_shapes() {
    seed(2);
    for i in 10000 {
        let x = rand(0, W);
        let y = rand(0, H);
        let c = rand_color();
        match i % 8 {
            0 => gfx2d::rect(x, y, rand(4, 60), rand(4, 60), c),
            1 => gfx2d::rounded_rect(x, y, rand(10, 80), rand(10, 60), rand(2, 10), c),
            2 => gfx2d::ellipse(x, y, rand(4, 40), rand(4, 40), c),
            3 => gfx2d::rect_outline(x, y, rand(10, 60), rand(10, 60), rand(1, 4), c),
            4 => gfx2d::circle_outline(x, y, rand(5, 40), rand(0.5, 4), c),
            5 => gfx2d::pie(x, y, rand(5, 40), rand(0, TAU), rand(0, TAU), c),
            6 => gfx2d::arc(x, y, rand(5, 40), rand(0, TAU), rand(0, TAU), rand(1, 8), c, gfx2d::CAP_ROUND),
            _ => gfx2d::line(x, y, x + rand(-80, 80), y + rand(-80, 80), rand(0.5, 6), c, gfx2d::CAP_ROUND),
        }
    }
}

// Every shape under transforms of its own, pushed and popped by blocks.
fn transformed() {
    seed(3);
    for i in 10000 {
        gfx2d::translate(rand(0, W), rand(0, H)) {
            gfx2d::rotate(rand(0, TAU)) {
                gfx2d::scale(rand(0.5, 2)) {
                    gfx2d::rounded_rect(-10, -5, 20, 10, 3, rand_color());
                };
            };
        };
    }
}

// --- paints --------------------------------------------------------------------------

// Each gradient its own stops: a ramp each, baked on the CPU every frame.
fn gradients() {
    seed(4);
    for i in 2000 {
        let x = rand(0, W);
        let y = rand(0, H);
        let stops = [gfx2d::stop(0, rand_color()), gfx2d::stop(0.5, rand_color()), gfx2d::stop(1, rand_color())];
        if i % 2 == 0 {
            gfx2d::rounded_rect(x, y, 80, 50, 8, gfx2d::paint(gfx2d::linear_gradient(x, y, x + 80, y + 50, stops)));
        } else {
            gfx2d::circle(x, y, 30, gfx2d::paint(gfx2d::radial_gradient(x, y, 30, stops)));
        }
    }
}

// Many shapes sharing a few gradients: ramps and paint records shared.
fn shared_gradients() {
    seed(5);
    let a = gfx2d::linear(0, 0, W, 0, gfx2d::RED, gfx2d::BLUE);
    let b = gfx2d::radial(W / 2, H / 2, H, gfx2d::WHITE, gfx2d::BLACK);
    for i in 10000 {
        gfx2d::circle(rand(0, W), rand(0, H), rand(4, 20), if i % 2 == 0 { a } else { b });
    }
}

var sheet: gfx::Texture;
var other: gfx::Texture;

// Sprites from one sheet: one batch.
fn sprites() {
    seed(6);
    for i in 10000 {
        let k = (rand() * 16) as i64;
        gfx2d::image(sheet, gfx2d::rect_of(rand(0, W), rand(0, H), 32, 32),
                     gfx2d::rect_of((k % 4) * 64, (k / 4) * 64, 64, 64));
    }
}

// Two textures taking turns: a batch, and a draw call, per sprite.
fn sprites_alternating() {
    seed(7);
    for i in 2000 {
        gfx2d::image(if i % 2 == 0 { sheet } else { other }, gfx2d::rect_of(rand(0, W), rand(0, H), 32, 32));
    }
}

// --- paths -----------------------------------------------------------------------------

// Stars (not convex: the band tessellator) and circles (convex: a fan).
fn path_fills() {
    seed(8);
    for i in 1000 {
        var p = gfx2d::Path {};
        gfx2d::star(p, rand(0, W), rand(0, H), 5, rand(10, 40), rand(4, 15));
        gfx2d::fill(p, rand_color());
        var c = gfx2d::Path {};
        gfx2d::circle(c, rand(0, W), rand(0, H), rand(5, 40));
        gfx2d::fill(c, rand_color());
    }
}

// One large outline: 5,000 points round a noisy blob, not convex, not
// crossing itself (a coastline, a country on a map).
fn big_path() {
    seed(9);
    var p = gfx2d::Path {};
    for i in 5000 {
        let a = TAU * i / 5000;
        let r = 400 + 60 * sin(a * 7) + rand(-25, 25);
        let x = W / 2 + r * cos(a) * 1.6;
        let y = H / 2 + r * sin(a);
        if i == 0 { gfx2d::move_to(p, x, y); } else { gfx2d::line_to(p, x, y); }
    }
    gfx2d::close(p);
    gfx2d::fill(p, gfx2d::rgba(0x3366CC, 0.5));
}

// 150 random points across the target, closed: about 5,000 crossings,
// even-odd. The band tessellator's worst kind of input.
fn self_crossing() {
    seed(14);
    var p = gfx2d::Path {};
    for i in 150 {
        let x = rand(0, W);
        let y = rand(0, H);
        if i == 0 { gfx2d::move_to(p, x, y); } else { gfx2d::line_to(p, x, y); }
    }
    gfx2d::close(p);
    gfx2d::fill(p, gfx2d::rgba(0xCC3366, 0.5), gfx2d::EVEN_ODD);
}

// A chart: 20 series of 1,000 points each, round joins.
fn chart() {
    seed(10);
    var pts: float2[>..] = [];
    for s in 20 {
        pts.resize(0);
        var y = rand(100, H - 100);
        for i in 1000 {
            y = clamp(y + rand(-8, 8), 0.0, H);
            pts.push(float2 { (i * W / 1000.0) as f32, y as f32 });
        }
        gfx2d::polyline(pts, 2, rand_color(), gfx2d::CAP_ROUND, gfx2d::JOIN_ROUND);
    }
}

// Dashed, curved strokes: dashing, round caps and flattening.
fn dashed() {
    seed(11);
    for i in 500 {
        var p = gfx2d::Path {};
        gfx2d::circle(p, rand(0, W), rand(0, H), rand(10, 60));
        gfx2d::stroke(p, gfx2d::Stroke { width: 2, cap: gfx2d::CAP_ROUND, dash: [6, 4] }, rand_color());
    }
}

// --- text --------------------------------------------------------------------------------

let LOREM = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. ";

var page: u8[>..] = [];

// A page of 14px text in lines of its own: about 9,000 glyphs, all in the
// atlas after the first frame.
fn text_page() {
    gfx2d::text(10, 10, page, gfx2d::TextStyle { size: 14, line_spacing: 1.0 }, gfx2d::BLACK);
}

// The same text as one paragraph wrapped to 1,900 pixels.
var paragraph: u8[>..] = [];
fn text_wrapped() {
    gfx2d::text(10, 10, paragraph, gfx2d::TextStyle { size: 14, wrap_width: 1900 }, gfx2d::BLACK);
}

// Short labels at many sizes, turning: what a HUD or chart draws.
fn text_labels() {
    seed(12);
    for i in 1000 {
        gfx2d::translate(rand(0, W), rand(0, H)) {
            gfx2d::rotate(rand(-0.3, 0.3)) {
                gfx2d::text(0, 0, "Label 1234", rand(10, 40), rand_color());
            };
        };
    }
}

// Every glyph of the font rasterized again each frame: the atlas emptied
// first. What the first frame with new text costs.
fn glyph_raster() {
    gfx2d::reset_atlas();
    var chars: u8[>..] = [];
    for c in 32..127 { chars.push(c as u8); }
    gfx2d::text(10, 10, chars, 24, gfx2d::BLACK);
    gfx2d::text(10, 60, "àáâãäåæçèéêëìíîïñòóôõöøùúûüýÿ ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÑÒÓÔÕÖØÙÚÛÜÝ €£¥©®™—–…→←", 24, gfx2d::BLACK);
}

// --- clips and layers ------------------------------------------------------------------

// 100 rounded-rect clips, 100 shapes in each: analytic clips cost shading.
fn clips() {
    seed(15);
    for k in 100 {
        let x = rand(0, W - 200);
        let y = rand(0, H - 150);
        gfx2d::clip_rounded_rect(x, y, 200, 150, 20) {
            for i in 100 { gfx2d::circle(x + rand(-20, 220), y + rand(-20, 170), rand(4, 20), rand_color()); }
        };
    }
}

// 20 star-shaped path clips: a mask pass each.
fn path_clips() {
    seed(16);
    for k in 20 {
        var p = gfx2d::Path {};
        let x = rand(100, W - 100);
        let y = rand(100, H - 100);
        gfx2d::star(p, x, y, 5, 90, 40);
        gfx2d::clip_path(p) {
            for i in 50 { gfx2d::rect(x - 100 + i * 4, y - 100, 2, 200, rand_color()); }
        };
    }
}

// 20 layers at half opacity: a pass and a composite each.
fn layers() {
    seed(17);
    for k in 20 {
        gfx2d::layer(0.5) {
            for i in 50 { gfx2d::circle(rand(0, W), rand(0, H), rand(10, 40), rand_color()); }
        };
    }
}

// 10 layers in modes that need the backdrop: a copy pass more each.
fn blend_layers() {
    seed(18);
    gfx2d::rect(0, 0, W, H, gfx2d::linear(0, 0, W, H, gfx2d::NAVY, gfx2d::ORANGE));
    for k in 10 {
        gfx2d::layer(gfx2d::LayerDesc { blend: (gfx2d::BLEND_SCREEN + k % 8) as i32 }) {
            for i in 20 { gfx2d::circle(rand(0, W), rand(0, H), rand(20, 80), rand_color()); }
        };
    }
}

// One blurred layer and one drop shadow, the whole target: four blur passes.
fn blur() {
    seed(19);
    gfx2d::layer(gfx2d::LayerDesc { blur: 8, shadow: gfx2d::rgba(0x000000, 0.5),
                                    shadow_offset: float2 { 8, 8 }, shadow_blur: 12 }) {
        for i in 200 { gfx2d::rounded_rect(rand(0, W), rand(0, H), 80, 50, 10, rand_color()); }
    };
}

// 2,000 box shadows under 2,000 cards.
fn box_shadows() {
    seed(20);
    for i in 2000 {
        let x = rand(0, W);
        let y = rand(0, H);
        gfx2d::box_shadow(x, y + 4, 60, 40, 8, 12, gfx2d::rgba(0x000000, 0.4));
        gfx2d::rounded_rect(x, y, 60, 40, 8, gfx2d::WHITE);
    }
}

// --- a scene ------------------------------------------------------------------------------

var panel: gfx::Texture;

// Something like an application's frame: 60 panels with title bars,
// buttons, labels, icons and a chart each.
fn ui_scene() {
    seed(13);
    let label = gfx2d::TextStyle { size: 13 };
    let title = gfx2d::TextStyle { size: 15 };
    for row in 6 {
        for col in 10 {
            let x = 10.0 + col * 190;
            let y = 10.0 + row * 178;
            box_shadow_stand_in(x, y);
            gfx2d::nine_slice(panel, gfx2d::rect_of(x, y, 180, 168), float4 { 8, 8, 8, 8 });
            gfx2d::rounded_rect(x + 4, y + 4, 172, 24, float4 { 6, 6, 0, 0 },
                                gfx2d::linear(0, y, 0, y + 24, gfx2d::rgb(0x4A6FA5), gfx2d::rgb(0x2E4A75)));
            gfx2d::text(x + 12, y + 8, "Panel title", title, gfx2d::WHITE);
            for b in 3 {
                let bx = x + 10 + b * 56;
                gfx2d::rounded_rect(bx, y + 136, 50, 22, 5, gfx2d::rgb(0xDDE6F0));
                gfx2d::rounded_rect_outline(bx, y + 136, 50, 22, 5, 1, gfx2d::rgb(0x8899AA));
                gfx2d::text(bx + 25, y + 140, "OK", gfx2d::TextStyle { size: 13, align: gfx2d::ALIGN_CENTER }, gfx2d::BLACK);
            }
            gfx2d::text(x + 12, y + 36, "Value: 42.0", label, gfx2d::BLACK);
            gfx2d::star(x + 160, y + 44, 5, 8, 3.5, gfx2d::ORANGE);
            var pts: float2[16] = [float2_0; 16];
            for k in 16 { pts[k] = float2 { (x + 12 + k * 10.5) as f32, (y + 100 - rand(0, 40)) as f32 }; }
            gfx2d::polyline(pts, 1.5, gfx2d::rgb(0x2E4A75), gfx2d::CAP_ROUND, gfx2d::JOIN_ROUND);
        }
    }
}

fn box_shadow_stand_in(x: f64, y: f64) {
    // A soft shadow, until box_shadow exists: a radial-gradient-free
    // stand-in, a translucent rounded rect offset down.
    gfx2d::rounded_rect(x + 2, y + 3, 180, 168, 10, gfx2d::rgba(0x000000, 0.15));
}

// --- main -----------------------------------------------------------------------------------

fn make_texture<F>(w: i64, h: i64) -> gfx::Texture {
    var data: u8[>..] = [];
    for y in h {
        for x in w {
            let c: gfx2d::Color = F(x, y);
            let v = gfx2d::to_u32(c);
            data.append([((v >> 16) & 255) as u8, ((v >> 8) & 255) as u8, (v & 255) as u8, (v >> 24) as u8]);
        }
    }
    let t = gfx::texture2d(w, h);
    gfx::update_texture(t, data);
    t
}

fn main() {
    let argv = args();
    var i = 1;
    while i < argv.len {
        if argv[i] == "--frames" && i + 1 < argv.len {
            let n, ok = parse_int(argv[i + 1]);
            if ok { frames = n; }
            i++;
        } else if argv[i] == "--list" {
            listing = true;
        } else {
            selected.push(argv[i]);
        }
        i++;
    }
    if !listing {
        guard gfx::open_headless(W, H) else {
            print("gfx: ", gfx::error());
            return;
        }
        target = gfx::render_target(W, H, gfx::RGBA8);
        sheet = make_texture(256, 256) { x, y => gfx2d::hsv(((x / 64) + (y / 64) * 4) / 16.0, 0.7, 1.0) };
        other = make_texture(32, 32) { x, y => if (x + y) % 8 < 4 { gfx2d::WHITE } else { gfx2d::GRAY } };
        panel = make_texture(24, 24) { x, y =>
            let edge = x < 2 || y < 2 || x > 21 || y > 21;
            if edge { gfx2d::rgb(0x8899AA) } else { gfx2d::rgb(0xF4F6F8) }
        };
        for line in 70 {
            page.append(LOREM[0..min(LOREM.len, 135)]);
            page.push('\n');
        }
        for k in 40 { paragraph.append(LOREM); }
        print("gfx2d benchmarks: ", W, "x", H, ", ", gfx::driver(), ", ", frames, " frames each after ",
              WARMUP, " to warm up; medians in ms");
    }
    run("empty") { f => empty(); };
    run("circles") { f => circles(); };
    run("mixed_shapes") { f => mixed_shapes(); };
    run("transformed") { f => transformed(); };
    run("gradients") { f => gradients(); };
    run("shared_gradients") { f => shared_gradients(); };
    run("sprites") { f => sprites(); };
    run("sprites_alternating") { f => sprites_alternating(); };
    run("path_fills") { f => path_fills(); };
    run("big_path") { f => big_path(); };
    run("self_crossing") { f => self_crossing(); };
    run("chart") { f => chart(); };
    run("dashed") { f => dashed(); };
    run("text_page") { f => text_page(); };
    run("text_wrapped") { f => text_wrapped(); };
    run("text_labels") { f => text_labels(); };
    run("glyph_raster") { f => glyph_raster(); };
    run("clips") { f => clips(); };
    run("path_clips") { f => path_clips(); };
    run("layers") { f => layers(); };
    run("blend_layers") { f => blend_layers(); };
    run("blur") { f => blur(); };
    run("box_shadows") { f => box_shadows(); };
    run("ui_scene") { f => ui_scene(); };
    run("ui_scene_msaa", 4) { f => ui_scene(); };
    if !listing { gfx::close(); }
}
