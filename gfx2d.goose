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
import paint;
import path;

// --- instances: src/shaders/shape.glsl ------------------------------------------

let KIND_RECT: u32 = 0;
let KIND_ELLIPSE: u32 = 1;
let KIND_PIE: u32 = 2;
let KIND_ARC: u32 = 3;
let KIND_ARC_BUTT: u32 = 4;

let FLAG_STROKE: u32 = 1;
// A rectangle's sides drawn hard (shape.glsl): where pieces meet.
let FLAG_HARD_LEFT: u32 = 2;
let FLAG_HARD_TOP: u32 = 4;
let FLAG_HARD_RIGHT: u32 = 8;
let FLAG_HARD_BOTTOM: u32 = 16;

// One shape, as the shaders read it from a storage buffer: std430 lays
// these fields out with no padding, 112 bytes.
struct Instance {
    m: float4,              // a, b, c, d of the local-to-pixel transform
    t: float2,              // its translation
    kind: u32,
    flags: u32,
    geom: float4,
    radii: float4,
    color: float4,
    lm: float4,             // local space to the paint's space
    lt: float2,
    paint: u32,             // in paints; 0: the color alone
    pad 4
}

// One paint, as src/shaders/paint.glsl reads it: 96 bytes in std430.
struct PaintGPU {
    kind: u32,
    spread: u32,
    image_mode: u32,        // IMAGE_*, or IMAGE_NONE
    flags: u32,             // PAINT_SCREEN | wrap << 4
    g0: float4,
    g1: float4,             // radius, 0, the ramp's row, opacity
    im: float4,
    it: float4,             // tx, ty, 1 for a part of the texture, 0
    src: float4,
}

let IMAGE_NONE: u32 = 255;
let PAINT_SCREEN: u32 = 1;
let INSTANCE_SIZE = 112;
let PAINT_SIZE = 96;

// One vertex of a tessellated path, as src/shaders/mesh.vert reads it.
struct MeshVertex {
    pos: float2,            // pixels
    user: float2,           // the space it was drawn in, for its paint
    color: float4,
    alpha: f32,             // coverage
    paint: u32,
}

// The shaders' uniform blocks, rounded to 16 bytes as std140 does.
struct FrameUniforms { view: float4, base: u32, pad 12 }
struct BlendUniforms { blend: u32, pad 12 }

// How a line or an arc ends.
let CAP_BUTT = 0;       // at the end point
let CAP_ROUND = 1;      // a half circle past it
let CAP_SQUARE = 2;     // half the width past it

// --- state -------------------------------------------------------------------------

// What gfx2d keeps of the GPU, made again when gfx is opened again.
struct Renderer {
    opened: i64 = -1,                   // the gfx::open_count() these were made under
    pipelines: gfx::Pipeline[4] = [gfx::Pipeline { 0 }; 4],     // shapes, by BLEND_*
    mesh_pipelines: gfx::Pipeline[4] = [gfx::Pipeline { 0 }; 4],
    vertices: gfx::Buffer = gfx::Buffer { 0 },
    vertex_bytes: i64 = 0,
    indices: gfx::Buffer = gfx::Buffer { 0 },
    index_bytes: i64 = 0,
    instances: gfx::Buffer = gfx::Buffer { 0 },
    instance_bytes: i64 = 0,
    paints: gfx::Buffer = gfx::Buffer { 0 },
    paint_bytes: i64 = 0,
    ramps: gfx::Texture = gfx::Texture { 0 },   // RAMP_WIDTH wide, a gradient a row
    ramp_rows: i64 = 0,
    white: gfx::Texture = gfx::Texture { 0 },   // bound where a paint has no image
    // By filter * 3 + wrap: FILTER_* and gfx's REPEAT, MIRROR, CLAMP.
    samplers: gfx::Sampler[6] = [gfx::Sampler { 0 }; 6],
}
var renderer: Renderer;

// What one draw call draws: a run of shape instances, or of mesh indices;
// one blend mode, one image.
let BATCH_SHAPES = 0;
let BATCH_MESH = 1;
struct Batch { kind: i64, first: i64, count: i64, blend: i32, texture: gfx::Texture, sampler: i64 }

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
var mesh_vertices: MeshVertex[>..<] = [];
var mesh_indices: u32[>..<] = [];
var batches: Batch[>..<] = [];
var paints: PaintGPU[>..<] = [];
var ramp_gradients: Gradient[>..<] = [];    // the frame's ramps, a row each
var ramp_pixels: u8[>..<] = [];
var saved: Affine[>..<] = [];               // push()'s transforms

// What the last end() drew.
struct Stats { instances: i64, triangles: i64, draws: i64, paints: i64, ramps: i64 }
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
    mesh_vertices.resize(0);
    mesh_indices.resize(0);
    batches.resize(0);
    saved.resize(0);
    ramp_gradients.resize(0);
    ramp_pixels.resize(0);
    paints.resize(0);
    // Paint 0: the instance's color alone.
    paints.push(PaintGPU { image_mode: IMAGE_NONE, g1: float4 { 0.0, 0.0, 0.0, 1.0 }, .. });
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
    renderer = Renderer { opened: gfx::open_count() };
    let modes: i32[4] = [gfx::BLEND_PREMULTIPLIED, gfx::BLEND_ADD, gfx::BLEND_MULTIPLY,
                         gfx::BLEND_NONE];
    let mesh_vs = embed_shader("src/shaders/mesh.vert");
    let mesh_fs = embed_shader("src/shaders/mesh.frag");
    for mode, i in modes {
        renderer.pipelines[i] = gfx::pipeline(vs, fs, gfx::PipelineDesc { blend: mode });
        renderer.mesh_pipelines[i] = gfx::pipeline(mesh_vs, mesh_fs, gfx::PipelineDesc { blend: mode });
    }
    let filters: i32[2] = [gfx::LINEAR, gfx::NEAREST];
    let wraps: i32[3] = [gfx::REPEAT, gfx::MIRROR, gfx::CLAMP];
    for f, i in filters {
        for w, j in wraps { renderer.samplers[i * 3 + j] = gfx::sampler(f, w); }
    }
    renderer.white = gfx::texture2d(1, 1);
    let white: u8[4] = [255, 255, 255, 255];
    gfx::update_texture(renderer.white, white);
}

// Puts `data` in a buffer of at least its size, made again larger when it
// has outgrown the one there.
fn upload(b: gfx::Buffer&, capacity: i64&, usage: i64, data: const u8[:]) {
    if data.len == 0 { return; }
    if data.len > capacity {
        if capacity > 0 { gfx::release(b); }
        capacity = max(data.len, max(capacity * 2, 16384));
        b = gfx::buffer(usage, capacity, data);
    } else {
        gfx::update_buffer(b, data);
    }
}

fn upload_ramps() {
    let rows = ramp_gradients.len;
    if rows == 0 { return; }
    if rows > renderer.ramp_rows {
        if renderer.ramp_rows > 0 { gfx::release(renderer.ramps); }
        renderer.ramp_rows = max(rows, max(renderer.ramp_rows * 2, 16));
        renderer.ramps = gfx::texture2d(RAMP_WIDTH, renderer.ramp_rows);
    }
    gfx::update_texture(renderer.ramps, gfx::Region { w: RAMP_WIDTH, h: rows as i32 },
                        ramp_pixels);
}

fn flush_batches() {
    last_stats = Stats { instances: instances.len, triangles: mesh_indices.len / 3,
                         draws: batches.len, paints: paints.len - 1, ramps: ramp_gradients.len };
    if batches.len == 0 && !state.clear { return; }
    ensure_renderer();
    if batches.len > 0 {
        upload(renderer.instances, renderer.instance_bytes, gfx::BUFFER_STORAGE, bytes_of(instances));
        upload(renderer.vertices, renderer.vertex_bytes, gfx::BUFFER_VERTEX, bytes_of(mesh_vertices));
        upload(renderer.indices, renderer.index_bytes, gfx::BUFFER_INDEX, bytes_of(mesh_indices));
        upload(renderer.paints, renderer.paint_bytes, gfx::BUFFER_STORAGE, bytes_of(paints));
        upload_ramps();
    }
    let info = gfx::texture_info(state.target);
    var pass = gfx::PassDesc { clear_color: state.clear,
                               color_value: premultiplied(state.clear_color), .. };
    pass.color[0] = state.target;
    guard gfx::begin_pass(pass) else { return; }
    let ramps = if renderer.ramp_rows > 0 { renderer.ramps } else { renderer.white };
    for b in batches {
        if b.kind == BATCH_SHAPES {
            gfx::bind(renderer.pipelines[b.blend]);
            gfx::bind_storage_buffer(gfx::VERTEX, 0, renderer.instances);
        } else {
            gfx::bind(renderer.mesh_pipelines[b.blend]);
            gfx::bind_vertex_buffer(renderer.vertices);
            gfx::bind_index_buffer(renderer.indices, 4);
        }
        gfx::bind_storage_buffer(gfx::FRAGMENT, 0, renderer.paints);
        gfx::bind_texture(gfx::FRAGMENT, 0, ramps, renderer.samplers[2]);   // linear, clamped
        let image = if b.texture.id == 0 { renderer.white } else { b.texture };
        gfx::bind_texture(gfx::FRAGMENT, 1, image, renderer.samplers[b.sampler]);
        gfx::uniforms(gfx::VERTEX, 0, FrameUniforms {
            view: float4 { info.width, info.height, 0.0, 0.0 }, base: b.first as u32 });
        gfx::uniforms(gfx::FRAGMENT, 0, BlendUniforms { blend: b.blend as u32 });
        if b.kind == BATCH_SHAPES { gfx::draw(b.count * 6); }
        else { gfx::draw_indexed(b.count, 1, b.first, 0, 0); }
    }
    gfx::end_pass();
}

// The row of the frame's ramp atlas holding g's ramp, added if no
// gradient so far has the same one.
fn ramp_row(g: Gradient) -> i64 {
    for other, i in ramp_gradients {
        if same_ramp(other, g) { return i; }
    }
    ramp_gradients.push(g);
    append_ramp(g, ramp_pixels);
    ramp_gradients.len - 1
}

// p's index in the frame's paints, added unless it is the last one added.
fn paint_index(p: Paint) -> u32 {
    let g = p.gradient;
    var gpu = PaintGPU {
        kind: g.kind as u32,
        spread: g.spread as u32,
        image_mode: IMAGE_NONE,
        flags: if p.space == SPACE_SCREEN { PAINT_SCREEN } else { 0 },
        g1: float4 { g.radius, 0.0, 0.0, p.opacity },
        ..
    };
    if g.kind != GRADIENT_NONE {
        gpu.g1.z = ramp_row(g);
        if g.kind == GRADIENT_LINEAR {
            gpu.g0 = float4 { g.p0.x, g.p0.y, g.p1.x, g.p1.y };
        } else if g.kind == GRADIENT_RADIAL {
            // The focal point inside the circle, where the gradient is
            // defined everywhere.
            var f = g.p1;
            let off = f - g.p0;
            let d = length(off);
            if d > g.radius * 0.99 && d > 0.0 { f = g.p0 + off * (g.radius * 0.99 / d); }
            gpu.g0 = float4 { g.p0.x, g.p0.y, f.x, f.y };
        } else {
            gpu.g0 = float4 { g.p0.x, g.p0.y, g.angle, 0.0 };
        }
    }
    let img = p.image;
    if img.texture.id != 0 {
        let inv, ok = invert(img.placement);
        if ok {
            gpu.image_mode = p.image_mode as u32;
            gpu.flags |= ((img.wrap as u32) & 3) << 4;
            gpu.im = float4 { inv.a, inv.b, inv.c, inv.d };
            let part = img.src.w != 0.0 && img.src.h != 0.0;
            gpu.it = float4 { inv.tx, inv.ty, if part { 1.0 } else { 0.0 }, 0.0 };
            gpu.src = float4 { img.src.x, img.src.y, img.src.w, img.src.h };
        } else {
            // Placed with no area: none of it shows.
            gpu.g1.w = 0.0;
        }
    }
    let n = paints.len;
    if n > 1 && paints[n - 1] == gpu { return (n - 1) as u32; }
    paints.push(gpu);
    n as u32
}

// Records one shape: `local` places its local space under the current
// transform. A Color paints it alone; a Paint as paint.goose says.
// How a Color or a Paint is drawn: its color, its paint record, and what
// its batch needs.
struct PaintKey { color: float4, paint: u32, blend: i32, texture: gfx::Texture, sampler: i64 }

fn paint_key(c: Color) -> PaintKey {
    PaintKey { color: to_float4(c), paint: 0, blend: BLEND_NORMAL, texture: gfx::Texture { 0 },
               sampler: 2 }
}
fn paint_key(p: Paint) -> PaintKey {
    let img = p.image;
    let has_image = img.texture.id != 0;
    let wrap = if img.wrap == WRAP_REPEAT { 0 } else if img.wrap == WRAP_MIRROR { 1 } else { 2 };
    let sampler = (if img.filter == FILTER_NEAREST { 3 } else { 0 }) + wrap;
    PaintKey { color: to_float4(p.color), paint: paint_index(p), blend: clamp(p.blend, 0, 3),
               texture: if has_image { img.texture } else { gfx::Texture { 0 } },
               sampler: if has_image { sampler } else { 2 } }
}

fn drawing() -> bool {
    if !state.drawing { misuse("drawing outside a frame: begin() first"); }
    state.drawing
}

// Records one shape: `local` places its local space under the current
// transform. A Color paints it alone; a Paint as paint.goose says.
fn add(kind: u32, flags: u32, local: Affine, geom: float4, radii: float4, c) {
    guard drawing();
    let k = paint_key(c);
    let m = mul(state.transform, local);
    instances.push(Instance { m: float4 { m.a, m.b, m.c, m.d }, t: float2 { m.tx, m.ty },
                              kind: kind, flags: flags, geom: geom, radii: radii, color: k.color,
                              lm: float4 { local.a, local.b, local.c, local.d },
                              lt: float2 { local.tx, local.ty }, paint: k.paint });
    batch(BATCH_SHAPES, instances.len - 1, 1, k);
}

// Puts `count` more instances or indices from `first` in the last batch,
// or a new one.
fn batch(kind: i64, first: i64, count: i64, k: PaintKey) {
    let blend = k.blend;
    let texture = k.texture;
    let sampler = k.sampler;
    // A batch is one blend mode and one image. A shape with no image fits
    // any batch of its blend mode (it samples the white texture, or
    // whatever is bound, and ignores it), and a batch with no image yet
    // takes the first image to come.
    let n = batches.len;
    if n > 0 {
        let last .= batches[n - 1];
        if last.kind == kind && last.blend == blend {
            if texture.id == 0 || (last.texture == texture && last.sampler == sampler) {
                last.count += count;
                return;
            }
            if last.texture.id == 0 {
                last.texture = texture;
                last.sampler = sampler;
                last.count += count;
                return;
            }
        }
    }
    batches.push(Batch { kind: kind, first: first, count: count, blend: blend, texture: texture,
                         sampler: sampler });
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
// gfx2d draws in f32. Every shape takes a Color or a Paint (paint.goose)
// as `c`. An outline is `width` wide and centered on the shape's edge.

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

fn rect(x: f64, y: f64, w: f64, h: f64, c) {
    add(KIND_RECT, 0, box_at(x, y, w, h), box_geom(w, h, 0.0), no_radii(), c);
}
fn rect(r: Rect, c) { rect(r.x, r.y, r.w, r.h, c); }
fn rect_outline(x: f64, y: f64, w: f64, h: f64, width: f64, c) {
    add(KIND_RECT, FLAG_STROKE, box_at(x, y, w, h), box_geom(w, h, width), no_radii(), c);
}
fn rect_outline(r: Rect, width: f64, c) { rect_outline(r.x, r.y, r.w, r.h, width, c); }

fn rounded_rect(x: f64, y: f64, w: f64, h: f64, r: f64, c) {
    rounded_rect(x, y, w, h, radii(r), c);
}
// Each corner its own radius: top left, top right, bottom right, bottom left.
fn rounded_rect(x: f64, y: f64, w: f64, h: f64, radii: float4, c) {
    add(KIND_RECT, 0, box_at(x, y, w, h), box_geom(w, h, 0.0), fit_radii(w, h, radii), c);
}
fn rounded_rect(r: Rect, radius: f64, c) { rounded_rect(r.x, r.y, r.w, r.h, radius, c); }
fn rounded_rect_outline(x: f64, y: f64, w: f64, h: f64, r: f64, width: f64, c) {
    rounded_rect_outline(x, y, w, h, radii(r), width, c);
}
fn rounded_rect_outline(x: f64, y: f64, w: f64, h: f64, radii: float4, width: f64, c) {
    add(KIND_RECT, FLAG_STROKE, box_at(x, y, w, h), box_geom(w, h, width),
        fit_radii(w, h, radii), c);
}
fn rounded_rect_outline(r: Rect, radius: f64, width: f64, c) {
    rounded_rect_outline(r.x, r.y, r.w, r.h, radius, width, c);
}

fn circle(cx: f64, cy: f64, r: f64, c) { ellipse(cx, cy, r, r, c); }
fn circle(center: float2, r: f64, c) { ellipse(center.x, center.y, r, r, c); }
fn circle_outline(cx: f64, cy: f64, r: f64, width: f64, c) {
    ellipse_outline(cx, cy, r, r, width, c);
}
fn circle_outline(center: float2, r: f64, width: f64, c) {
    ellipse_outline(center.x, center.y, r, r, width, c);
}

fn ellipse(cx: f64, cy: f64, rx: f64, ry: f64, c) {
    add(KIND_ELLIPSE, 0, translation(cx, cy), geom(abs(rx), abs(ry), 0.0, 0.0), no_radii(), c);
}
fn ellipse_outline(cx: f64, cy: f64, rx: f64, ry: f64, width: f64, c) {
    add(KIND_ELLIPSE, FLAG_STROKE, translation(cx, cy), geom(abs(rx), abs(ry), width, 0.0),
        no_radii(), c);
}

// The band between radii r0 and r1.
fn ring(cx: f64, cy: f64, r0: f64, r1: f64, c) {
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
fn pie(cx: f64, cy: f64, r: f64, a0: f64, a1: f64, c) {
    let m, h = sector(cx, cy, a0, a1);
    if h >= PI {
        circle(cx, cy, r, c);
        return;
    }
    add(KIND_PIE, 0, m, geom(abs(r), h, 0.0, 0.0), no_radii(), c);
}
fn pie_outline(cx: f64, cy: f64, r: f64, a0: f64, a1: f64, width: f64, c) {
    let m, h = sector(cx, cy, a0, a1);
    if h >= PI {
        circle_outline(cx, cy, r, width, c);
        return;
    }
    add(KIND_PIE, FLAG_STROKE, m, geom(abs(r), h, width, 0.0), no_radii(), c);
}

// Part of the circle of radius r, from angle a0 to a1, `width` wide and
// centered on the circle.
fn arc(cx: f64, cy: f64, r: f64, a0: f64, a1: f64, width: f64, c, cap: i64 = CAP_BUTT) {
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
fn line(x0: f64, y0: f64, x1: f64, y1: f64, width: f64, c, cap: i64 = CAP_BUTT) {
    let dx = x1 - x0;
    let dy = y1 - y0;
    let len = sqrt(dx * dx + dy * dy);
    let hw = abs(width) * 0.5;
    let m = mul(translation((x0 + x1) * 0.5, (y0 + y1) * 0.5), rotation(atan2(dy, dx)));
    let along = if cap == CAP_BUTT { len * 0.5 } else { len * 0.5 + hw };
    let r = if cap == CAP_ROUND { hw } else { 0.0 };
    add(KIND_RECT, 0, m, geom(along, hw, 0.0, 0.0), radii(r), c);
}
fn line(a: float2, b: float2, width: f64, c, cap: i64 = CAP_BUTT) {
    line(a.x, a.y, b.x, b.y, width, c, cap);
}

// --- images ----------------------------------------------------------------------------
//
// An image is a rectangle painted with a texture: so it takes the current
// transform, antialiased edges, and a Paint's blend and opacity like any
// shape. `tint` multiplies it; `filter` is FILTER_LINEAR or, for pixel
// art, FILTER_NEAREST.

fn texture_rect(t: gfx::Texture) -> Rect {
    let info = gfx::texture_info(t);
    rect_of(0, 0, info.width, info.height)
}

// The whole texture at (x, y), at its size in pixels.
fn image(t: gfx::Texture, x: f64, y: f64, tint: Color = WHITE, filter: i64 = FILTER_LINEAR) {
    let whole = texture_rect(t);
    draw_image(t, rect_of(x, y, whole.w, whole.h), whole, false, tint, filter, 0);
}
// The whole texture, stretched over dst.
fn image(t: gfx::Texture, dst: Rect, tint: Color = WHITE, filter: i64 = FILTER_LINEAR) {
    draw_image(t, dst, texture_rect(t), false, tint, filter, 0);
}
// The part `src` of the texture (pixels: a sprite in a sheet) over dst. A
// negative dst.w or dst.h flips it.
fn image(t: gfx::Texture, dst: Rect, src: Rect, tint: Color = WHITE,
         filter: i64 = FILTER_LINEAR) {
    draw_image(t, dst, src, true, tint, filter, 0);
}

fn draw_image(t: gfx::Texture, dst: Rect, src: Rect, part: bool, tint: Color, filter: i64,
              hard: u32) {
    guard src.w != 0.0 && src.h != 0.0 else { return; }
    let placement = Affine { dst.w / src.w, 0.0, 0.0, dst.h / src.h, dst.x, dst.y };
    let img = Image { texture: t, placement: placement,
                      src: if part { src } else { Rect { 0.0, 0.0, 0.0, 0.0 } },
                      wrap: WRAP_CLAMP, filter: filter as i32 };
    add(KIND_RECT, hard, box_at(dst.x, dst.y, dst.w, dst.h), box_geom(dst.w, dst.h, 0.0),
        no_radii(), Paint { color: tint, image: img });
}

// A nine-slice (nine-patch): `src`, a part of the texture, cut by `insets`
// (pixels in from its left, top, right and bottom), drawn over dst with
// the corners at their size, the edges stretched along their length and
// the middle both ways. For panels and buttons whose borders must not
// stretch.
fn nine_slice(t: gfx::Texture, dst: Rect, src: Rect, insets: float4, tint: Color = WHITE,
              filter: i64 = FILTER_LINEAR) {
    let sx: f32[4] = [src.x, src.x + insets.x, src.x + src.w - insets.z, src.x + src.w];
    let sy: f32[4] = [src.y, src.y + insets.y, src.y + src.h - insets.w, src.y + src.h];
    let dx: f32[4] = [dst.x, dst.x + insets.x, dst.x + dst.w - insets.z, dst.x + dst.w];
    let dy: f32[4] = [dst.y, dst.y + insets.y, dst.y + dst.h - insets.w, dst.y + dst.h];
    for j in 3 {
        for i in 3 {
            let s = Rect { sx[i], sy[j], sx[i + 1] - sx[i], sy[j + 1] - sy[j] };
            let d = Rect { dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j] };
            // Sides inside the whole are hard, so the pieces meet seamlessly.
            var hard: u32 = 0;
            if i > 0 { hard |= FLAG_HARD_LEFT; }
            if j > 0 { hard |= FLAG_HARD_TOP; }
            if i < 2 { hard |= FLAG_HARD_RIGHT; }
            if j < 2 { hard |= FLAG_HARD_BOTTOM; }
            if s.w > 0.0 && s.h > 0.0 && d.w > 0.0 && d.h > 0.0 {
                draw_image(t, d, s, true, tint, filter, hard);
            }
        }
    }
}
// The whole texture as the nine-slice.
fn nine_slice(t: gfx::Texture, dst: Rect, insets: float4, tint: Color = WHITE,
              filter: i64 = FILTER_LINEAR) {
    nine_slice(t, dst, texture_rect(t), insets, tint, filter);
}

// --- paths -------------------------------------------------------------------------------
//
// Fills and strokes of paths (path.goose), and the shapes made of straight
// lines: polygons, polylines, triangles, regular polygons and stars. They
// are tessellated each time they are drawn, into triangles with an
// antialiasing fringe, in pixels.

// Pixels the curves of paths may be off by. Flattened points lie on the
// curve, so a flattened outline is inside it, by up to this much: small
// enough that the area lost is a fraction of what antialiasing blurs.
let TOLERANCE: f32 = 0.1;

var flat_pts: float2[>..<] = [];
var flat_contours: Contour[>..<] = [];
var dash_pts: float2[>..<] = [];
var dash_cs: Contour[>..<] = [];
var outline_pts: float2[>..<] = [];
var outline_cs: Contour[>..<] = [];
var tess_out: TessVertex[>..<] = [];
var tess_idx: u32[>..<] = [];

// The current transform's scale: how many pixels a unit is, on average.
fn pixel_scale() -> f32 { sqrt(abs(determinant(state.transform))) }

// tess_out and tess_idx, in pixels, as a mesh painted with c, its alpha
// multiplied by k.
fn add_mesh(c, k: f32) {
    if tess_idx.len == 0 { return; }
    let key = paint_key(c);
    let inv, ok = invert(state.transform);
    let base = mesh_vertices.len as u32;
    for v in tess_out {
        mesh_vertices.push(MeshVertex { pos: v.p, user: if ok { apply(inv, v.p) } else { v.p },
                                        color: key.color, alpha: v.alpha * k, paint: key.paint });
    }
    let first = mesh_indices.len;
    for i in tess_idx { mesh_indices.push(base + i); }
    batch(BATCH_MESH, first, tess_idx.len, key);
}

// The flattened contours in flat_pts, in pixels, filled.
fn fill_flat(c, rule: i64) {
    tess_out.resize(0);
    tess_idx.resize(0);
    fill_triangles(flat_pts, flat_contours, rule, 1.0, tess_out, tess_idx);
    add_mesh(c, 1.0);
}

// The path filled by `rule`, NONZERO or EVEN_ODD.
fn fill(p: const Path&, c, rule: i64 = NONZERO) {
    guard drawing();
    flat_pts.resize(0);
    flat_contours.resize(0);
    flatten(p, state.transform, TOLERANCE, flat_pts, flat_contours);
    fill_flat(c, rule);
}

// The path stroked `width` wide, with miter joins and butt caps.
fn stroke(p: const Path&, width: f64, c) { stroke(p, Stroke { width: width as f32 }, c); }

// The path stroked as `s` says. The stroke is made in the space the path is
// drawn in, so under a stretching transform it stretches too, as a pen
// would; with s.pixels, in pixels, the same width whatever the transform.
fn stroke(p: const Path&, s: Stroke, c) {
    guard drawing();
    let scale = if s.pixels { 1.0 } else { max(pixel_scale(), 0.000001) };
    // Pixels in the stroke's space.
    let px = 1.0 / scale;
    // Thinner than a pixel: a pixel wide, as faint as it is thin.
    let width_px = abs(s.width) * scale;
    let k = min(width_px, 1.0);
    let half = max(width_px, 1.0) * 0.5 * px;
    flat_pts.resize(0);
    flat_contours.resize(0);
    flatten(p, if s.pixels { state.transform } else { IDENTITY }, TOLERANCE * px, flat_pts,
            flat_contours);
    outline_pts.resize(0);
    outline_cs.resize(0);
    if s.dash.len > 0 {
        dash_pts.resize(0);
        dash_cs.resize(0);
        dash_contours(flat_pts, flat_contours, s.dash, s.dash_offset, dash_pts, dash_cs);
        stroke_outline(dash_pts, dash_cs, half, s.join, s.cap, s.miter_limit, TOLERANCE * px,
                       outline_pts, outline_cs);
    } else {
        stroke_outline(flat_pts, flat_contours, half, s.join, s.cap, s.miter_limit,
                       TOLERANCE * px, outline_pts, outline_cs);
    }
    if !s.pixels {
        for &q in outline_pts { q = apply(state.transform, q); }
    }
    tess_out.resize(0);
    tess_idx.resize(0);
    fill_triangles(outline_pts, outline_cs, NONZERO, 1.0, tess_out, tess_idx);
    add_mesh(c, k);
}

// Through the points, closed, filled by the nonzero rule.
fn polygon(points: const float2[:], c) {
    guard drawing();
    flat_pts.resize(0);
    flat_contours.resize(0);
    for q in points { flat_pts.push(apply(state.transform, q)); }
    flat_contours.push(Contour { first: 0, count: points.len, closed: true });
    fill_flat(c, NONZERO);
}
fn triangle(x0: f64, y0: f64, x1: f64, y1: f64, x2: f64, y2: f64, c) {
    polygon([pt(x0, y0), pt(x1, y1), pt(x2, y2)], c);
}
fn triangle(a: float2, b: float2, d: float2, c) { polygon([a, b, d], c); }
fn quad(a: float2, b: float2, d: float2, e: float2, c) { polygon([a, b, d, e], c); }

// Strokes through points: open, or closed back to the first.
fn polyline(points: const float2[:], width: f64, c, cap: i64 = CAP_BUTT, join: i64 = JOIN_MITER) {
    var p = Path {};
    p.polygon(points, false);
    stroke(p, Stroke { width: width as f32, join: join as i32, cap: cap as i32 }, c);
}
fn polygon_outline(points: const float2[:], width: f64, c, join: i64 = JOIN_MITER) {
    var p = Path {};
    p.polygon(points, true);
    stroke(p, Stroke { width: width as f32, join: join as i32 }, c);
}

// n corners on the circle of radius r about (cx, cy), the first at `angle`.
fn regular_polygon(cx: f64, cy: f64, r: f64, n: i64, c, angle: f64 = -PI / 2) {
    var p = Path {};
    p.regular_polygon(cx, cy, r, n, angle);
    fill(p, c);
}
// n points at radius `outer`, the corners between them at `inner`.
fn star(cx: f64, cy: f64, n: i64, outer: f64, inner: f64, c, angle: f64 = -PI / 2) {
    var p = Path {};
    p.star(cx, cy, n, outer, inner, angle);
    fill(p, c);
}
