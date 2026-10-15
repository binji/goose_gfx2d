// The shape pipeline's fragment shader: the shape's signed distance at this
// pixel (negative inside, in local units), turned into coverage over about
// one pixel, whatever the transform, times the paint's color. The output
// suits the batch's blend mode (Frame.blend). The distance functions are
// Inigo Quilez's.
#include "shape.glsl"
#include "paint.glsl"
#include "sdf.glsl"
#include "clip.glsl"

layout(location = 0) in vec2 v_local;
layout(location = 1) flat in uint v_kind;
layout(location = 2) flat in uint v_flags;
layout(location = 3) flat in vec4 v_geom;
layout(location = 4) flat in vec4 v_radii;
layout(location = 5) flat in vec4 v_color;
layout(location = 6) in vec2 v_user;
layout(location = 7) flat in uint v_paint;
layout(location = 8) flat in uint v_clip;

layout(set = 2, binding = 0) uniform sampler2D ramp;
layout(set = 2, binding = 1) uniform sampler2D image;
layout(set = 2, binding = 2) uniform sampler2D glyphs;
layout(set = 2, binding = 3) uniform sampler2D mask;
layout(std430, set = 2, binding = 4) readonly buffer Paints { Paint paints[]; };
layout(std430, set = 2, binding = 5) readonly buffer Clips { Clip clips[]; };

// text.goose's glyph atlas: a value of GLYPH_ON_EDGE on the outline, more
// inside, GLYPH_DIST_SCALE per pixel of distance.
const float GLYPH_ON_EDGE = 128.0 / 255.0;
const float GLYPH_DIST_SCALE = 128.0 / 6.0 / 255.0;
layout(set = 3, binding = 0) uniform Blend { uint blend; uint batch_clip; };

layout(location = 0) out vec4 result;

#include "clip_coverage.glsl"

void main() {
    vec2 p = v_local;
    // One pixel in local units: the local distance a step to the next pixel
    // covers, averaged over x and y, so rotation leaves it alone.
    float px = max(0.5 * (length(dFdx(p)) + length(dFdy(p))), 1e-6);
    vec2 sc = vec2(sin(v_geom.y), cos(v_geom.y));
    float d;
    float hard = 1.0;
    if (v_kind == KIND_RECT) {
        // Hard sides are moved out of antialiasing's reach, and tested by
        // the pixel's center instead.
        vec2 b = v_geom.xy;
        vec2 lo = -b;
        vec2 hi = b;
        float away = 4.0 * px;
        if ((v_flags & FLAG_HARD_LEFT) != 0u) { lo.x -= away; hard *= step(-b.x, p.x); }
        if ((v_flags & FLAG_HARD_TOP) != 0u) { lo.y -= away; hard *= step(-b.y, p.y); }
        if ((v_flags & FLAG_HARD_RIGHT) != 0u) { hi.x += away; hard *= 1.0 - step(b.x, p.x); }
        if ((v_flags & FLAG_HARD_BOTTOM) != 0u) { hi.y += away; hard *= 1.0 - step(b.y, p.y); }
        d = sd_rounded_box(p - (lo + hi) * 0.5, (hi - lo) * 0.5, v_radii);
    } else if (v_kind == KIND_ELLIPSE) {
        d = sd_ellipse(p, v_geom.xy);
    } else if (v_kind == KIND_PIE) {
        d = sd_pie(p, sc, v_geom.x);
    } else if (v_kind == KIND_ARC) {
        d = sd_arc(p, sc, v_geom.x, v_geom.w);
    } else if (v_kind == KIND_SHADOW) {
        d = 0.0;
    } else if (v_kind == KIND_GLYPH) {
        // Kept to the glyph's own texels: the quad reaches past them, by
        // more atlas pixels the smaller the text.
        vec2 size = vec2(textureSize(glyphs, 0));
        vec2 t = clamp(p + v_geom.xy, vec2(0.5), v_radii.zw - 0.5);
        float value = textureLod(glyphs, (v_radii.xy + t) / size, 0.0).r;
        d = (GLYPH_ON_EDGE - value) / GLYPH_DIST_SCALE;
    } else {
        d = max(abs(length(p) - v_geom.x) - v_geom.w, sd_pie(p, sc, v_geom.x + v_geom.w + 1.0));
    }

    float k = hard;
    if ((v_flags & FLAG_STROKE) != 0u) {
        // A stroke thinner than a pixel is drawn a pixel wide, as faint as
        // it is thin, so it neither vanishes nor flickers as it moves.
        float width = v_geom.z;
        k = min(width / px, 1.0);
        d = abs(d) - max(width, px) * 0.5;
    }
    float coverage = clamp(0.5 - d / px, 0.0, 1.0) * k;
    if (v_kind == KIND_SHADOW) coverage = box_shadow(p, v_geom.xy, v_radii.x, max(v_geom.z, 1e-3));
    coverage *= clip_coverage(v_clip, gl_FragCoord.xy);

    // The paint is read in every fragment, uniformly, so the derivatives
    // the image's sampling takes stay defined.
    vec4 c = paint_color(paints[v_paint], v_color, v_user, gl_FragCoord.xy, ramp, image) * coverage;
    result = blend_out(c, blend);
}
