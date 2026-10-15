// gfx2d's clips and layers, each around a block.
//
//   gfx2d::clip_rounded_rect(20, 20, 200, 120, 16) {
//       gfx2d::image(photo, gfx2d::rect_of(0, 0, 240, 160));     // only inside the rounded rect
//   };
//   gfx2d::layer(gfx2d::LayerDesc { opacity: 0.5, blend: gfx2d::BLEND_SCREEN,
//                                   shadow: gfx2d::rgba(0x000000, 0.4),
//                                   shadow_offset: float2 { 4, 6 }, shadow_blur: 6 }) {
//       gfx2d::circle(100, 100, 40, gfx2d::RED);     // drawn together, then composited
//       gfx2d::circle(130, 100, 40, gfx2d::BLUE);
//   };
//
// A clip limits what the draws in its block cover, antialiased at its edge,
// and nested clips limit each other. A rectangle, rounded rectangle, circle
// or ellipse clip is worked out in the fragment shader, under any transform,
// for nothing but a few instructions a pixel. A path clip is drawn into a
// mask texture first, in a pass of its own.
//
// A layer draws its block into a texture of its own, and then composites it
// where it was opened: at an opacity, as one (overlaps inside it do not
// show through each other), by a blend mode, blurred, with a drop shadow.
// The fixed-function modes (NORMAL, ADD, MULTIPLY, REPLACE) composite in one
// draw; the others need what is under the layer, so the target is copied
// first, and the copy blended with in the shader. Each layer costs passes:
// the layer's, one for the target after it, and two per blur.
//
// Layers and masks are textures of the target's size, from a pool kept
// between frames.

namespace gfx2d;

import std;
import vec;
import math;
import gfx;
import color;
import transform;
import paint;
import path;

// --- clips ---------------------------------------------------------------------------

fn add_clip(c: ClipGPU, mask: gfx::Texture) -> u32 {
    clips.push(c);
    clip_masks.push(mask);
    (clips.len - 1) as u32
}

// The block drawn under a clip of `kind`: a box or ellipse of half extents
// `half`, centered on the origin of `local`, under the current transform.
fn clip_shape<F>(kind: u32, local: Affine, half: float2, radii: float4) {
    guard drawing();
    let parent = state.clip;
    let m = mul(state.transform, local);
    let inv, ok = invert(m);
    // A transform that flattens the clip to nothing leaves nothing inside.
    let h = if ok { half } else { float2_0 };
    state.clip = add_clip(ClipGPU { m: float4 { inv.a, inv.b, inv.c, inv.d }, t: float2 { inv.tx, inv.ty },
                                    kind: kind, parent: parent, geom: float4 { h.x, h.y, 0.0, 0.0 },
                                    radii: radii }, clip_masks[parent]);
    F();
    state.clip = parent;
}

fn clip_rect<F>(x: f64, y: f64, w: f64, h: f64) {
    clip_shape(CLIP_BOX, box_at(x, y, w, h), float2 { (abs(w) * 0.5) as f32, (abs(h) * 0.5) as f32 },
               float4_0) { F(); };
}
fn clip_rect<F>(r: Rect) { clip_rect(r.x, r.y, r.w, r.h) { F(); }; }
fn clip_rounded_rect<F>(x: f64, y: f64, w: f64, h: f64, r: f64) {
    clip_rounded_rect(x, y, w, h, radii(r)) { F(); };
}
// Each corner its own radius: top left, top right, bottom right, bottom left.
fn clip_rounded_rect<F>(x: f64, y: f64, w: f64, h: f64, corner_radii: float4) {
    clip_shape(CLIP_BOX, box_at(x, y, w, h), float2 { (abs(w) * 0.5) as f32, (abs(h) * 0.5) as f32 },
               fit_radii(w, h, corner_radii)) { F(); };
}
fn clip_ellipse<F>(cx: f64, cy: f64, rx: f64, ry: f64) {
    clip_shape(CLIP_ELLIPSE, translation(cx, cy), float2 { abs(rx) as f32, abs(ry) as f32 },
               float4_0) { F(); };
}
fn clip_circle<F>(cx: f64, cy: f64, r: f64) { clip_ellipse(cx, cy, r, r) { F(); }; }

// The block drawn only inside the path, filled by `rule`: the path is drawn
// into a mask texture (under the clips already in effect, so it carries
// them), and everything in the block multiplied by it.
fn clip_path<F>(p: const Path&, rule: i64 = NONZERO) {
    guard drawing();
    let parent = state.clip;
    let back = passes[state.pass];
    let mask = pooled(state.width, state.height, gfx::R8, 1);
    open_pass(mask, gfx::Texture { 0 }, 1, true);
    fill(p, WHITE, rule);
    open_pass(back.target, back.resolve, back.samples, false);
    state.clip = add_clip(ClipGPU { kind: CLIP_MASK, parent: 0,
                                    geom: float4 { state.width, state.height, 0.0, 0.0 }, .. }, mask);
    F();
    state.clip = parent;
}

// --- layers --------------------------------------------------------------------------

// Paint.blend's fixed-function modes are paint.goose's BLEND_NORMAL, ADD,
// MULTIPLY and REPLACE. These are for layers only: the W3C's separable
// blend modes, and two Porter-Duff ones.
let BLEND_SCREEN = 4;
let BLEND_OVERLAY = 5;
let BLEND_DARKEN = 6;
let BLEND_LIGHTEN = 7;
let BLEND_COLOR_DODGE = 8;
let BLEND_COLOR_BURN = 9;
let BLEND_HARD_LIGHT = 10;
let BLEND_SOFT_LIGHT = 11;
let BLEND_DIFFERENCE = 12;
let BLEND_EXCLUSION = 13;
let BLEND_ERASE = 14;       // what is under the layer, cleared where the layer is (destination-out)
let BLEND_KEEP = 15;        // what is under the layer, kept only where the layer is (destination-in)

struct LayerDesc {
    opacity: f32 = 1.0,
    blend: i32 = 0,                             // BLEND_NORMAL
    blur: f32 = 0.0,                            // the layer blurred: a gaussian's sigma, pixels
    shadow: Color = Color { 0.0, 0.0, 0.0, 0.0 },   // a drop shadow's color; transparent: none
    shadow_offset: float2 = float2 { 0.0, 0.0 },
    shadow_blur: f32 = 0.0,                     // the shadow's sigma, pixels
}

// `src` blurred by sigma both ways, into a texture of the pool: within
// `b`, what was drawn, grown by the blur's reach (3 sigma, and a pixel).
// The first pass reads 3 sigma across and writes what the second reads,
// 3 sigma further up and down; outside what either writes the pool's
// textures hold whatever they did.
fn blurred(src: gfx::Texture, sigma: f32, b: Bounds) -> gfx::Texture {
    let across = pooled(state.width, state.height, gfx::RGBA8, 1);
    let out = pooled(state.width, state.height, gfx::RGBA8, 1);
    let reach = 3.0 * sigma + 1.0;
    blur_pass(src, across, float2 { 1.0, 0.0 }, sigma, scissor_of(inflate(b, float2 { reach, 2.0 * reach })));
    blur_pass(across, out, float2 { 0.0, 1.0 }, sigma, scissor_of(inflate(b, float2 { reach, reach })));
    out
}

// A composite, as a batch: its index in composites.
fn composite(layer: gfx::Texture, backdrop: gfx::Texture, u: CompositeUniforms, scissor: Scissor) -> i64 {
    composites.push(Composite { layer: layer, backdrop: backdrop, u: u, scissor: scissor });
    let pipeline = if u.blend <= BLEND_REPLACE { u.blend as i32 } else { BLEND_REPLACE as i32 };
    batches.push(Batch { kind: BATCH_COMPOSITE, first: composites.len - 1, count: 1, blend: pipeline,
                         texture: gfx::Texture { 0 }, sampler: 2, mask: clip_masks[u.clip], clip: 0 });
    composites.len - 1
}

// The block drawn into a layer, composited as `d` says. The layer's
// texture is the target's size, from the pool, but only the pixels the
// block draws, grown by the blur's and the shadow's reach, are touched:
// cleared (by a composite of nothing, scissored, in place of clearing it
// all), blurred and composited. A block that draws nothing leaves no
// passes behind.
fn layer<F>(d: LayerDesc) {
    guard drawing();
    let back = passes[state.pass];
    let clip = state.clip;
    let tex = pooled(state.width, state.height, gfx::RGBA8, 1);
    open_pass(tex, gfx::Texture { 0 }, 1, false);
    let layer_pass = state.pass;
    // The clear, its scissor set once the block has drawn.
    let clearing = composite(renderer.white, gfx::Texture { 0 },
                             CompositeUniforms { opacity: 0.0, blend: BLEND_REPLACE as u32, .. }, Scissor { .. });
    layer_bounds.push(Bounds { .. });
    // The layer's contents are clipped where it is composited.
    state.clip = 0;
    F();
    state.clip = clip;
    close_pass();
    let drawn = layer_bounds.pop();
    let shadowed = d.shadow.a > 0.0;
    let reach = 3.0 * max(d.blur, if shadowed { d.shadow_blur } else { 0.0 }) + 1.0;
    let cleared = scissor_of(inflate(drawn, float2 { 2.0 * reach, 2.0 * reach }));
    if is_empty(drawn) || is_nothing(cleared) {
        // Nothing drawn, or nothing in the target: the layer's pass is left
        // out, and nothing is composited.
        open_pass(back.target, back.resolve, back.samples, false);
        passes[layer_pass].end_batch = passes[layer_pass].first_batch;
        return;
    }
    // A layer covering most of the target is cleared the plain way, which
    // is cheaper than a draw over most of it; the clearing composite is
    // then skipped (a width of -1).
    if cleared.w * cleared.h * 2 > state.width * state.height {
        passes[layer_pass].clear = true;
        composites[clearing].scissor = Scissor { 0, 0, -1, 0 };
    } else {
        composites[clearing].scissor = cleared;
    }
    let content_bounds = inflate(drawn, float2 { 3.0 * d.blur + 1.0, 3.0 * d.blur + 1.0 });
    let content = if d.blur > 0.0 { blurred(tex, d.blur, drawn) } else { tex };
    var shadow = gfx::Texture { 0 };
    var shadow_bounds = Bounds { .. };
    if shadowed {
        shadow = if d.shadow_blur > 0.0 { blurred(tex, d.shadow_blur, drawn) } else { tex };
        shadow_bounds = offset(inflate(drawn, float2 { 3.0 * d.shadow_blur + 1.0, 3.0 * d.shadow_blur + 1.0 }),
                               d.shadow_offset);
    }
    open_pass(back.target, back.resolve, back.samples, false);
    if shadow.id != 0 {
        let sc = scissor_of(shadow_bounds);
        if !is_nothing(sc) {
            composite(shadow, gfx::Texture { 0 },
                      CompositeUniforms { tint: to_float4(d.shadow), offset: d.shadow_offset,
                                          opacity: d.opacity, blend: BLEND_NORMAL as u32, shadow: 1,
                                          clip: clip }, sc);
        }
    }
    // KEEP changes the target wherever the layer is not, so it needs all of it.
    let sc = if d.blend == BLEND_KEEP { Scissor { 0, 0, state.width, state.height } } else { scissor_of(content_bounds) };
    if !is_nothing(sc) {
        var backdrop = gfx::Texture { 0 };
        if d.blend > BLEND_REPLACE {
            // What is under the layer, copied, to blend with: from the target, or
            // where a multisampled one resolves.
            backdrop = pooled(state.width, state.height, gfx::RGBA8, 1);
            close_pass();
            blur_pass(if back.resolve.id != 0 { back.resolve } else { back.target }, backdrop, float2_0, 0.0, sc);
            open_pass(back.target, back.resolve, back.samples, false);
        }
        composite(content, backdrop, CompositeUniforms { opacity: d.opacity, blend: clamp(d.blend, 0, 15) as u32,
                                                         clip: clip, .. }, sc);
    }
    // What this layer puts on the target counts as drawn by the one around it.
    if in_layer() {
        let outer .= layer_bounds[layer_bounds.len - 1];
        let mine = if shadowed { union(content_bounds, shadow_bounds) } else { content_bounds };
        extend(outer, mine.lo);
        extend(outer, mine.hi);
    }
}
fn layer<F>(opacity: f64) { layer(LayerDesc { opacity: opacity as f32 }) { F(); }; }
