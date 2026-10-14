// gfx2d: 2D drawing on gfx. Shapes (rectangles, rounded rectangles,
// circles, ellipses, pies, arcs, rings, lines), filled or outlined, under a
// current transform, antialiased by their signed distance in the fragment
// shader. docs/design.md is the plan; this is its first phase.
//
// Drawing happens between begin and end, or in frame's block:
//
//   while gfx::frame() {
//       gfx2d::frame(gfx2d::WHITE) {
//           gfx2d::circle(400, 300, 100, gfx2d::RED);
//       };
//   }
//
// Draws are recorded and drawn at end(), in the order they were made, in a
// gfx pass of gfx2d's own: so begin/end go between a program's own passes,
// not inside one, and 2D drawing goes before or after 3D drawing and ui as
// the program likes.
//
// Coordinates are pixels, y down, as gfx's screen has them; angles are
// radians, clockwise on the screen. Colors are color.goose's; geometry is
// transform.goose's.
//
// Errors are gfx's two kinds. Using gfx2d wrongly (drawing outside begin and
// end, a pop with nothing pushed, begin twice) is printed as it happens and
// aborts the program at end().

namespace gfx2d;

import std;
import vec;
import math;
import os;
import gfx;
import color;
import transform;

// --- instances: src/shaders/shape.glsl ------------------------------------------

let KIND_RECT: u32 = 0;
let KIND_ELLIPSE: u32 = 1;
let KIND_PIE: u32 = 2;
let KIND_ARC: u32 = 3;
let KIND_ARC_BUTT: u32 = 4;

let FLAG_STROKE: u32 = 1;

// One shape, as the shaders read it from a storage buffer: std430 lays
// these fields out with no padding, 80 bytes.
struct Instance {
    m: float4,              // a, b, c, d of the local-to-pixel transform
    t: float2,              // its translation
    kind: u32,
    flags: u32,
    geom: float4,
    radii: float4,
    color: float4,
}

// The vertex shader's uniform block; std140 rounds it to 32 bytes.
struct FrameUniforms { view: float4, base: u32, pad 12 }

// How a line or an arc ends.
let CAP_BUTT = 0;       // at the end point
let CAP_ROUND = 1;      // a half circle past it
let CAP_SQUARE = 2;     // half the width past it

// --- state -------------------------------------------------------------------------

// What gfx2d keeps of the GPU, made again when gfx is opened again.
struct Renderer {
    opened: i64 = -1,                   // the gfx::open_count() these were made under
    shape: gfx::Pipeline,
    instances: gfx::Buffer,
    capacity: i64,                      // instances the buffer holds
}
var renderer: Renderer;

// A run of instances drawn with one draw call.
struct Batch { first: i64, count: i64 }

// The frame being recorded.
struct FrameState {
    drawing: bool,
    target: gfx::Texture,
    clear: bool,
    clear_color: Color,
    transform: Affine,
}
var state = FrameState { transform: IDENTITY, .. };

var instances: Instance[>..<] = [];
var batches: Batch[>..<] = [];
var saved: Affine[>..<] = [];           // push()'s transforms

// What the last end() drew.
struct Stats { instances: i64, draws: i64 }
var last_stats: Stats;

var misuse_count = 0;
var last_misuse: u8[>..] = [];

fn misuse(what: const u8[:]) {
    misuse_count++;
    last_misuse.resize(0);
    last_misuse.append(what);
    write_stderr(str("gfx2d: ", what, "\n"));
}

// Aborts, saying why, if gfx2d has been used wrongly.
fn check() {
    if misuse_count > 0 { abort(str("gfx2d: ", last_misuse)); }
}

fn stats() -> Stats { last_stats }

// --- frames --------------------------------------------------------------------------

// Starts drawing into `target`, a color target, cleared to `clear`.
fn begin(target: gfx::Texture, clear: Color) { begin_into(target, true, clear); }
// Over what `target` holds.
fn begin(target: gfx::Texture) { begin_into(target, false, TRANSPARENT); }
// Into gfx's screen.
fn begin_screen(clear: Color) { begin(gfx::screen(), clear); }
fn begin_screen() { begin(gfx::screen()); }

fn begin_into(target: gfx::Texture, clear: bool, clear_color: Color) {
    if state.drawing { misuse("begin: already drawing; end() the last frame first"); }
    state = FrameState { drawing: true, target: target, clear: clear, clear_color: clear_color,
                         transform: IDENTITY };
    instances.resize(0);
    batches.resize(0);
    saved.resize(0);
}

// Draws everything recorded since begin.
fn end() {
    if !state.drawing { misuse("end: not drawing; begin() first"); }
    if saved.len > 0 { misuse(str("end: ", saved.len, " push() without a pop()")); }
    check();
    state.drawing = false;
    flush_batches();
}

// The screen cleared to `clear`, the block drawn, and end().
fn frame<F>(clear: Color) {
    begin_screen(clear);
    F();
    end();
}
// Into a target of the program's.
fn draw_into<F>(target: gfx::Texture, clear: Color) {
    begin(target, clear);
    F();
    end();
}

fn ensure_renderer() {
    if renderer.opened == gfx::open_count() { return; }
    let vs = embed_shader("src/shaders/shape.vert");
    let fs = embed_shader("src/shaders/shape.frag");
    renderer = Renderer {
        opened: gfx::open_count(),
        shape: gfx::pipeline(vs, fs, gfx::PipelineDesc { blend: gfx::BLEND_PREMULTIPLIED }),
        instances: gfx::Buffer { 0 },
        capacity: 0,
    };
}

fn flush_batches() {
    last_stats = Stats { instances: instances.len, draws: batches.len };
    if instances.len == 0 && !state.clear { return; }
    ensure_renderer();
    if instances.len > 0 {
        if instances.len > renderer.capacity {
            if renderer.capacity > 0 { gfx::release(renderer.instances); }
            renderer.capacity = max(instances.len, max(renderer.capacity * 2, 256));
            renderer.instances = gfx::buffer(gfx::BUFFER_STORAGE, renderer.capacity * 80,
                                             bytes_of(instances));
        } else {
            gfx::update_buffer(renderer.instances, bytes_of(instances));
        }
    }
    let info = gfx::texture_info(state.target);
    var pass = gfx::PassDesc { clear_color: state.clear,
                               color_value: premultiplied(state.clear_color), .. };
    pass.color[0] = state.target;
    guard gfx::begin_pass(pass) else { return; }
    gfx::bind(renderer.shape);
    if instances.len > 0 { gfx::bind_storage_buffer(gfx::VERTEX, 0, renderer.instances); }
    for b in batches {
        gfx::uniforms(gfx::VERTEX, 0, FrameUniforms {
            view: float4 { info.width, info.height, 0.0, 0.0 }, base: b.first as u32 });
        gfx::draw(b.count * 6);
    }
    gfx::end_pass();
}

// Records one shape: `local` places its local space under the current
// transform.
fn add(kind: u32, flags: u32, local: Affine, geom: float4, radii: float4, c: Color) {
    if !state.drawing {
        misuse("drawing outside a frame: begin() first");
        return;
    }
    let m = mul(state.transform, local);
    instances.push(Instance { m: float4 { m.a, m.b, m.c, m.d }, t: float2 { m.tx, m.ty },
                              kind: kind, flags: flags, geom: geom, radii: radii,
                              color: to_float4(c) });
    let n = batches.len;
    if n > 0 && batches[n - 1].first + batches[n - 1].count == instances.len - 1 {
        batches[n - 1].count++;
    } else {
        batches.push(Batch { first: instances.len - 1, count: 1 });
    }
}

// --- the current transform -------------------------------------------------------------

fn current_transform() -> Affine { state.transform }
fn set_transform(m: Affine) { state.transform = m; }
fn reset_transform() { state.transform = IDENTITY; }
// m applied before the current transform: what follows is drawn in m's space.
fn transform(m: Affine) { state.transform = mul(state.transform, m); }
fn translate(x: f64, y: f64) { transform(translation(x, y)); }
fn rotate(angle: f64) { transform(rotation(angle)); }
fn rotate_about(angle: f64, cx: f64, cy: f64) { transform(rotation_about(angle, cx, cy)); }
fn scale(sx: f64, sy: f64) { transform(scaling(sx, sy)); }
fn scale(s: f64) { transform(scaling(s)); }
fn skew(ax: f64, ay: f64) { transform(skewing(ax, ay)); }

// Saves the current transform, for pop() to restore.
fn push() { saved.push(state.transform); }
fn pop() {
    guard saved.len > 0 else {
        misuse("pop: nothing pushed");
        return;
    }
    state.transform = saved[saved.len - 1];
    saved.resize(saved.len - 1);
}

// The same, around a block: the transform is changed for the block, and
// restored after it.
fn transform<F>(m: Affine) {
    push();
    transform(m);
    F();
    pop();
}
fn translate<F>(x: f64, y: f64) { transform(translation(x, y)) { F(); }; }
fn rotate<F>(angle: f64) { transform(rotation(angle)) { F(); }; }
fn rotate_about<F>(angle: f64, cx: f64, cy: f64) {
    transform(rotation_about(angle, cx, cy)) { F(); };
}
fn scale<F>(sx: f64, sy: f64) { transform(scaling(sx, sy)) { F(); }; }
fn scale<F>(s: f64) { transform(scaling(s)) { F(); }; }
fn skew<F>(ax: f64, ay: f64) { transform(skewing(ax, ay)) { F(); }; }

// A point in pixels (the mouse's, say) in the current transform's space,
// and back.
fn to_local(p: float2) -> float2 {
    let inv, ok = invert(state.transform);
    if !ok { return p; }
    apply(inv, p)
}
fn to_pixels(p: float2) -> float2 { apply(state.transform, p) }

// --- shapes ------------------------------------------------------------------------------
//
// Scalars are f64, so that numbers of any type pass, f64 locals included;
// gfx2d draws in f32. Fills and outlines both take a Color; an outline is
// `width` wide and centered on the shape's edge.

fn no_radii() -> float4 { float4_0 }
// An instance's geom, in the shaders' f32.
fn geom(x: f64, y: f64, z: f64, w: f64) -> float4 { float4 { x as f32, y as f32, z as f32, w as f32 } }
fn radii(r: f64) -> float4 { geom(r, r, r, r) }

// A box from (x, y), w by h, in local space centered on the origin, and its
// geom: half its size, and the stroke's width.
fn box_at(x: f64, y: f64, w: f64, h: f64) -> Affine { translation(x + w * 0.5, y + h * 0.5) }
fn box_geom(w: f64, h: f64, stroke: f64) -> float4 { geom(abs(w) * 0.5, abs(h) * 0.5, stroke, 0.0) }

// Corner radii no larger than the box allows.
fn fit_radii(w: f64, h: f64, r: float4) -> float4 {
    let most = (min(abs(w), abs(h)) * 0.5) as f32;
    float4 { clamp(r.x, 0.0, most), clamp(r.y, 0.0, most), clamp(r.z, 0.0, most),
             clamp(r.w, 0.0, most) }
}

fn rect(x: f64, y: f64, w: f64, h: f64, c: Color) {
    add(KIND_RECT, 0, box_at(x, y, w, h), box_geom(w, h, 0.0), no_radii(), c);
}
fn rect(r: Rect, c: Color) { rect(r.x, r.y, r.w, r.h, c); }
fn rect_outline(x: f64, y: f64, w: f64, h: f64, width: f64, c: Color) {
    add(KIND_RECT, FLAG_STROKE, box_at(x, y, w, h), box_geom(w, h, width), no_radii(), c);
}
fn rect_outline(r: Rect, width: f64, c: Color) { rect_outline(r.x, r.y, r.w, r.h, width, c); }

fn rounded_rect(x: f64, y: f64, w: f64, h: f64, r: f64, c: Color) {
    rounded_rect(x, y, w, h, radii(r), c);
}
// Each corner its own radius: top left, top right, bottom right, bottom left.
fn rounded_rect(x: f64, y: f64, w: f64, h: f64, radii: float4, c: Color) {
    add(KIND_RECT, 0, box_at(x, y, w, h), box_geom(w, h, 0.0), fit_radii(w, h, radii), c);
}
fn rounded_rect(r: Rect, radius: f64, c: Color) { rounded_rect(r.x, r.y, r.w, r.h, radius, c); }
fn rounded_rect_outline(x: f64, y: f64, w: f64, h: f64, r: f64, width: f64, c: Color) {
    rounded_rect_outline(x, y, w, h, radii(r), width, c);
}
fn rounded_rect_outline(x: f64, y: f64, w: f64, h: f64, radii: float4, width: f64, c: Color) {
    add(KIND_RECT, FLAG_STROKE, box_at(x, y, w, h), box_geom(w, h, width),
        fit_radii(w, h, radii), c);
}
fn rounded_rect_outline(r: Rect, radius: f64, width: f64, c: Color) {
    rounded_rect_outline(r.x, r.y, r.w, r.h, radius, width, c);
}

fn circle(cx: f64, cy: f64, r: f64, c: Color) { ellipse(cx, cy, r, r, c); }
fn circle(center: float2, r: f64, c: Color) { ellipse(center.x, center.y, r, r, c); }
fn circle_outline(cx: f64, cy: f64, r: f64, width: f64, c: Color) {
    ellipse_outline(cx, cy, r, r, width, c);
}
fn circle_outline(center: float2, r: f64, width: f64, c: Color) {
    ellipse_outline(center.x, center.y, r, r, width, c);
}

fn ellipse(cx: f64, cy: f64, rx: f64, ry: f64, c: Color) {
    add(KIND_ELLIPSE, 0, translation(cx, cy), geom(abs(rx), abs(ry), 0.0, 0.0), no_radii(), c);
}
fn ellipse_outline(cx: f64, cy: f64, rx: f64, ry: f64, width: f64, c: Color) {
    add(KIND_ELLIPSE, FLAG_STROKE, translation(cx, cy), geom(abs(rx), abs(ry), width, 0.0),
        no_radii(), c);
}

// The band between radii r0 and r1.
fn ring(cx: f64, cy: f64, r0: f64, r1: f64, c: Color) {
    circle_outline(cx, cy, (r0 + r1) * 0.5, abs(r1 - r0), c);
}

// The local space of a sector from angle a0 to a1 (radians, clockwise),
// whose middle is +y, and half the angle it spans, PI for a whole circle
// or more. (The sector's distance function has a seam where a whole
// circle closes, so callers draw a circle for one.)
fn sector(cx: f64, cy: f64, a0: f64, a1: f64) -> Affine, f64 {
    let lo = min(a0, a1);
    let hi = max(a0, a1);
    let half_span = min((hi - lo) * 0.5, PI);
    return mul(translation(cx, cy), rotation((lo + hi) * 0.5 - PI * 0.5)), half_span;
}

// A slice of the circle of radius r, from angle a0 to angle a1.
fn pie(cx: f64, cy: f64, r: f64, a0: f64, a1: f64, c: Color) {
    let m, h = sector(cx, cy, a0, a1);
    if h >= PI {
        circle(cx, cy, r, c);
        return;
    }
    add(KIND_PIE, 0, m, geom(abs(r), h, 0.0, 0.0), no_radii(), c);
}
fn pie_outline(cx: f64, cy: f64, r: f64, a0: f64, a1: f64, width: f64, c: Color) {
    let m, h = sector(cx, cy, a0, a1);
    if h >= PI {
        circle_outline(cx, cy, r, width, c);
        return;
    }
    add(KIND_PIE, FLAG_STROKE, m, geom(abs(r), h, width, 0.0), no_radii(), c);
}

// Part of the circle of radius r, from angle a0 to a1, `width` wide and
// centered on the circle.
fn arc(cx: f64, cy: f64, r: f64, a0: f64, a1: f64, width: f64, c: Color, cap: i64 = CAP_BUTT) {
    var m, h = sector(cx, cy, a0, a1);
    let hw = abs(width) * 0.5;
    // A whole circle has no ends to cap.
    if h >= PI {
        circle_outline(cx, cy, r, width, c);
        return;
    }
    if cap == CAP_ROUND {
        add(KIND_ARC, 0, m, geom(abs(r), h, 0.0, hw), no_radii(), c);
        return;
    }
    // A square cap is a butt cap half the width further on, measured along
    // the circle.
    if cap == CAP_SQUARE && r > 0.0 { h = min(h + hw / r, PI); }
    add(KIND_ARC_BUTT, 0, m, geom(abs(r), h, 0.0, hw), no_radii(), c);
}

// From (x0, y0) to (x1, y1), `width` wide.
fn line(x0: f64, y0: f64, x1: f64, y1: f64, width: f64, c: Color, cap: i64 = CAP_BUTT) {
    let dx = x1 - x0;
    let dy = y1 - y0;
    let len = sqrt(dx * dx + dy * dy);
    let hw = abs(width) * 0.5;
    let m = mul(translation((x0 + x1) * 0.5, (y0 + y1) * 0.5), rotation(atan2(dy, dx)));
    let along = if cap == CAP_BUTT { len * 0.5 } else { len * 0.5 + hw };
    let r = if cap == CAP_ROUND { hw } else { 0.0 };
    add(KIND_RECT, 0, m, geom(along, hw, 0.0, 0.0), radii(r), c);
}
fn line(a: float2, b: float2, width: f64, c: Color, cap: i64 = CAP_BUTT) {
    line(a.x, a.y, b.x, b.y, width, c, cap);
}
