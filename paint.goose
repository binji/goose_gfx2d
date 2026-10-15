// gfx2d's paints: what colors the pixels a shape covers. A Paint is a
// color, or a gradient, optionally combined with an image, at an opacity,
// blended into the target by a blend mode. The types and the gradient
// ramps are here, in plain Goose (test/pure/paint.goose); gfx2d.goose puts
// them on the GPU.
//
// The shader paints in this order: the source (the color, or the gradient
// tinted by the color), the image combined with it by image_mode, then
// opacity, then the shape's coverage; the result is blended by `blend`.
//
//   gfx2d::rect(0, 0, 200, 100, gfx2d::linear(0, 0, 200, 0, gfx2d::RED, gfx2d::BLUE));
//   gfx2d::circle(100, 100, 50, gfx2d::Paint {
//       gradient: gfx2d::radial_gradient(100, 100, 50, [gfx2d::stop(0, gfx2d::WHITE),
//                                                       gfx2d::stop(1, gfx2d::NAVY)]),
//       image: gfx2d::image_pattern(noise, gfx2d::scaling(0.25)),
//       opacity: 0.8,
//   });
//
// Geometry in a paint (gradient points, an image's placement) is in the
// space the shape is drawn in, under the current transform, so the paint
// moves with the shape; Paint.space = SPACE_SCREEN pins it to the target's
// pixels instead.

namespace gfx2d;

import std;
import vec;
import math;
import gfx;
import color;
import transform;

// --- constants: src/shaders/paint.glsl ----------------------------------------------

// Gradient.kind.
let GRADIENT_NONE = 0;
let GRADIENT_LINEAR = 1;
let GRADIENT_RADIAL = 2;
let GRADIENT_CONIC = 3;

// Gradient.spread: what lies beyond the gradient's ends.
let SPREAD_PAD = 0;         // the end colors, on and on
let SPREAD_REPEAT = 1;      // the gradient again
let SPREAD_REFLECT = 2;     // the gradient again, back and forth

// Gradient.space: the colors between two stops are mixed in
let INTERPOLATE_SRGB = 0;   // sRGB's encoding, as CSS and most 2D APIs do
let INTERPOLATE_LINEAR = 1; // linear light
let INTERPOLATE_OKLAB = 2;  // OKLab: even-looking steps, no gray middle between complements

// Paint.image_mode: how the image's color combines with the source.
let IMAGE_MULTIPLY = 0;     // source x image: with a white source, the image as it is
let IMAGE_REPLACE = 1;      // the image alone
let IMAGE_ADD = 2;          // source + image
let IMAGE_MASK = 3;         // the source, where the image is opaque: its alpha only

// Image.wrap: what the image is beyond its edges.
let WRAP_CLAMP = 0;         // its edge pixels, on and on
let WRAP_REPEAT = 1;
let WRAP_MIRROR = 2;
let WRAP_DECAL = 3;         // transparent

// Image.filter.
let FILTER_LINEAR = 0;
let FILTER_NEAREST = 1;     // pixel art

// Paint.blend: how the painted color is blended into the target. The four
// gfx's fixed-function blending gives; the others (screen, overlay,
// erase, ...) are layers' (layer.goose), which read what is under them.
let BLEND_NORMAL = 0;       // over, with alpha
let BLEND_ADD = 1;          // added, by its alpha: light, glows
let BLEND_MULTIPLY = 2;     // multiplied: shadows, tinting what is there
let BLEND_REPLACE = 3;      // written as it is, alpha too; hard edges

// Paint.space.
let SPACE_LOCAL = 0;        // the space the shape is drawn in
let SPACE_SCREEN = 1;       // the target's pixels

let MAX_STOPS = 16;

// --- types ---------------------------------------------------------------------------

struct Stop { offset: f32, color: Color }

// Field defaults spell the constants' values (a default may run before any
// global is set), and say which.
struct Gradient {
    kind: i32 = 0,                  // GRADIENT_NONE
    p0: float2 = float2 { 0.0, 0.0 },   // linear: where t is 0; radial, conic: the center
    p1: float2 = float2 { 0.0, 0.0 },   // linear: where t is 1; radial: the focal point
    radius: f32 = 0.0,              // radial: where t is 1
    angle: f32 = 0.0,               // conic: where t is 0, radians clockwise from +x
    spread: i32 = 0,                // SPREAD_PAD
    space: i32 = 0,                 // INTERPOLATE_SRGB
    stops: Stop[..16] = [],         // offsets ascending, from 0 to 1
}

struct Image {
    texture: gfx::Texture = gfx::Texture { 0 },     // none: no image
    // Where the image's pixels go: image space, in pixels from the top left
    // of `src`, to the paint's space.
    placement: Affine = Affine { 1.0, 0.0, 0.0, 1.0, 0.0, 0.0 },
    src: Rect = Rect { 0.0, 0.0, 0.0, 0.0 },        // the part of the texture, in pixels; w 0: all
    wrap: i32 = 0,                  // WRAP_CLAMP
    filter: i32 = 0,                // FILTER_LINEAR
}

struct Paint {
    color: Color = Color { 1.0, 1.0, 1.0, 1.0 },   // the source, or the gradient's tint
    gradient: Gradient = Gradient { .. },
    image: Image = Image { .. },
    image_mode: i32 = 0,            // IMAGE_MULTIPLY
    opacity: f32 = 1.0,
    blend: i32 = 0,                 // BLEND_NORMAL
    space: i32 = 0,                 // SPACE_LOCAL
}

// --- building them ---------------------------------------------------------------------

fn stop(offset: f64, c: Color) -> Stop { Stop { offset as f32, c } }

fn with_stops(g: Gradient, stops: const Stop[:]) -> Gradient {
    var out = g;
    for s in stops {
        if out.stops.len < MAX_STOPS { out.stops.push(s); }
    }
    out
}

// From (x0, y0), where the stops' offset 0 is, to (x1, y1), offset 1.
// At most MAX_STOPS stops; ones after that are left out.
fn linear_gradient(x0: f64, y0: f64, x1: f64, y1: f64, stops: const Stop[:]) -> Gradient {
    with_stops(Gradient { kind: GRADIENT_LINEAR, p0: float2 { x0 as f32, y0 as f32 },
                          p1: float2 { x1 as f32, y1 as f32 } }, stops)
}
// Circles about (cx, cy): offset 0 at the center, 1 at `radius`.
fn radial_gradient(cx: f64, cy: f64, radius: f64, stops: const Stop[:]) -> Gradient {
    radial_gradient(cx, cy, radius, cx, cy, stops)
}
// Offset 0 at the focal point (fx, fy), which must be inside the circle:
// a highlight off center.
fn radial_gradient(cx: f64, cy: f64, radius: f64, fx: f64, fy: f64,
                   stops: const Stop[:]) -> Gradient {
    with_stops(Gradient { kind: GRADIENT_RADIAL, p0: float2 { cx as f32, cy as f32 },
                          p1: float2 { fx as f32, fy as f32 }, radius: abs(radius) as f32 }, stops)
}
// Around (cx, cy), clockwise from `angle`: a color wheel, a pie chart.
fn conic_gradient(cx: f64, cy: f64, angle: f64, stops: const Stop[:]) -> Gradient {
    with_stops(Gradient { kind: GRADIENT_CONIC, p0: float2 { cx as f32, cy as f32 },
                          angle: angle as f32 }, stops)
}

// An image to paint with: repeated by default, as a pattern, and placed
// by `placement` from the image's pixels into the paint's space.
fn image_pattern(t: gfx::Texture, placement: Affine = IDENTITY, wrap: i64 = WRAP_REPEAT,
                 filter: i64 = FILTER_LINEAR) -> Image {
    Image { texture: t, placement: placement, wrap: wrap as i32, filter: filter as i32 }
}

// Paints of one thing, for the shapes that take a Paint.
fn solid(c: Color) -> Paint { Paint { color: c } }
fn paint(g: Gradient) -> Paint { Paint { gradient: g } }
fn paint(i: Image) -> Paint { Paint { image: i } }
// Two-color gradients in one call.
fn linear(x0: f64, y0: f64, x1: f64, y1: f64, c0: Color, c1: Color) -> Paint {
    paint(linear_gradient(x0, y0, x1, y1, [stop(0, c0), stop(1, c1)]))
}
fn radial(cx: f64, cy: f64, radius: f64, inner: Color, outer: Color) -> Paint {
    paint(radial_gradient(cx, cy, radius, [stop(0, inner), stop(1, outer)]))
}
fn pattern(t: gfx::Texture) -> Paint { paint(image_pattern(t)) }

// The same paint with something changed.
fn with_opacity(p: Paint, opacity: f64) -> Paint {
    var out = p;
    out.opacity = opacity as f32;
    out
}
fn with_blend(p: Paint, blend: i64) -> Paint {
    var out = p;
    out.blend = blend as i32;
    out
}

// --- ramps ------------------------------------------------------------------------------

let RAMP_WIDTH = 256;

// The gradient's color at t from 0 to 1, as the GPU paints it: offsets
// made ascending (one below the one before counts as that one, as in CSS),
// the color before the first stop the first stop's and after the last the
// last's, mixed in the gradient's space.
fn gradient_at(g: Gradient, t: f32) -> Color {
    let n = g.stops.len;
    if n == 0 { return TRANSPARENT; }
    var prev = g.stops[0];
    if t <= prev.offset { return prev.color; }
    for i in 1..n {
        var s = g.stops[i];
        s.offset = max(s.offset, prev.offset);
        if t <= s.offset {
            let span = s.offset - prev.offset;
            let k = if span > 0.0 { (t - prev.offset) / span } else { 1.0 };
            return match g.space {
                INTERPOLATE_LINEAR => mix_linear(prev.color, s.color, k),
                INTERPOLATE_OKLAB => mix(prev.color, s.color, k),
                _ => mix_srgb(prev.color, s.color, k),
            };
        }
        prev = s;
    }
    prev.color
}

// The gradient's ramp: RAMP_WIDTH texels of RGBA8, premultiplied (so
// filtering between texels does not darken where alpha changes), texel i
// the color at i / (RAMP_WIDTH - 1).
fn append_ramp(g: Gradient, out: u8[>..<]&) {
    fn byte(x: f32) -> u8 { (saturate(x) * 255.0 + 0.5) as u8 }
    let n = g.stops.len;
    if g.space != INTERPOLATE_SRGB || n == 0 {
        for i in RAMP_WIDTH {
            let c = premultiplied(gradient_at(g, i / (RAMP_WIDTH - 1.0)));
            out.append([byte(c.x), byte(c.y), byte(c.z), byte(c.w)]);
        }
        return;
    }
    // In sRGB's encoding, premultiplied, a ramp is straight lines between
    // its stops' premultiplied colors: walked once, as gradient_at would
    // find them.
    var off: f32[16] = [0.0; 16];
    var pm: float4[16] = [float4_0; 16];
    for st, i in g.stops {
        off[i] = if i > 0 { max(st.offset, off[i - 1]) } else { st.offset };
        pm[i] = premultiplied(st.color);
    }
    var j = 1;
    for i in RAMP_WIDTH {
        let t: f32 = i / (RAMP_WIDTH - 1.0);
        var c = pm[n - 1];
        if t <= off[0] {
            c = pm[0];
        } else {
            while j < n && t > off[j] { j++; }
            if j < n {
                let span = off[j] - off[j - 1];
                let k = if span > 0.0 { (t - off[j - 1]) / span } else { 1.0 };
                c = lerp(pm[j - 1], pm[j], k);
            }
        }
        out.append([byte(c.x), byte(c.y), byte(c.z), byte(c.w)]);
    }
}

// Whether two gradients have the same ramp, as near as a ramp can show:
// what the ramp atlas shares a row by. Colors are compared as bytes and
// offsets to 1/65536, so a gradient animated by less than that keeps its
// row.
fn same_ramp(a: Gradient, b: Gradient) -> bool {
    if a.space != b.space || a.stops.len != b.stops.len { return false; }
    for s, i in a.stops {
        let t = b.stops[i];
        if to_u32(s.color) != to_u32(t.color) { return false; }
        if round(s.offset * 65536.0) != round(t.offset * 65536.0) { return false; }
    }
    true
}
