// A layer composited onto the target it was opened over: its texture
// (premultiplied, the target's size) at an offset, times opacity, or for a
// shadow its alpha alone in the tint's color; under the clip the layer was
// opened in; blended by a fixed-function mode (blend_out), or by one of the
// modes that need what is under it (backdrop, a copy of the target), which
// write the result whole.
#include "paint.glsl"
#include "sdf.glsl"
#include "clip.glsl"

layout(set = 2, binding = 0) uniform sampler2D layer;
layout(set = 2, binding = 1) uniform sampler2D backdrop;
layout(set = 2, binding = 2) uniform sampler2D mask;
layout(std430, set = 2, binding = 3) readonly buffer Clips { Clip clips[]; };
layout(set = 3, binding = 0) uniform Composite {
    vec4 tint;          // a shadow's color, straight
    vec2 offset;        // where the layer is drawn, from where it was
    float opacity;
    uint blend;         // BLEND_*
    uint shadow;        // 1: draw the alpha in the tint
    uint clip;
    vec2 pad;
};

layout(location = 0) out vec4 result;

#include "clip_coverage.glsl"

const uint BLEND_SCREEN = 4u;
const uint BLEND_OVERLAY = 5u;
const uint BLEND_DARKEN = 6u;
const uint BLEND_LIGHTEN = 7u;
const uint BLEND_COLOR_DODGE = 8u;
const uint BLEND_COLOR_BURN = 9u;
const uint BLEND_HARD_LIGHT = 10u;
const uint BLEND_SOFT_LIGHT = 11u;
const uint BLEND_DIFFERENCE = 12u;
const uint BLEND_EXCLUSION = 13u;
const uint BLEND_ERASE = 14u;
const uint BLEND_KEEP = 15u;

// The separable blend functions of the W3C's Compositing and Blending, on
// unpremultiplied colors: b the backdrop, s the source.
vec3 hard_light(vec3 b, vec3 s) {
    return mix(b * 2.0 * s, 1.0 - (1.0 - b) * (1.0 - (2.0 * s - 1.0)), step(0.5, s));
}
vec3 soft_light(vec3 b, vec3 s) {
    vec3 d = mix(sqrt(b), ((16.0 * b - 12.0) * b + 4.0) * b, step(b, vec3(0.25)));
    return mix(b + (2.0 * s - 1.0) * (d - b), b - (1.0 - 2.0 * s) * b * (1.0 - b), step(s, vec3(0.5)));
}
vec3 blend_fn(uint mode, vec3 b, vec3 s) {
    if (mode == BLEND_SCREEN) return b + s - b * s;
    if (mode == BLEND_OVERLAY) return hard_light(s, b);
    if (mode == BLEND_DARKEN) return min(b, s);
    if (mode == BLEND_LIGHTEN) return max(b, s);
    if (mode == BLEND_COLOR_DODGE) {
        return mix(min(vec3(1.0), b / max(1.0 - s, vec3(1e-5))), vec3(1.0), step(1.0, s)) * step(1e-5, b);
    }
    if (mode == BLEND_COLOR_BURN) {
        vec3 r = 1.0 - min(vec3(1.0), (1.0 - b) / max(s, vec3(1e-5)));
        return mix(mix(r, vec3(0.0), step(s, vec3(0.0))), vec3(1.0), step(1.0, b));
    }
    if (mode == BLEND_HARD_LIGHT) return hard_light(b, s);
    if (mode == BLEND_SOFT_LIGHT) return soft_light(b, s);
    if (mode == BLEND_DIFFERENCE) return abs(b - s);
    return b + s - 2.0 * b * s;     // BLEND_EXCLUSION
}

void main() {
    vec2 size = vec2(textureSize(layer, 0));
    vec2 uv = (gl_FragCoord.xy - offset) / size;
    vec4 s = textureLod(layer, uv, 0.0);
    // Past the layer's edge there is nothing, not its edge pixels again
    // (the sampler clamps): a shadow offset inward from the target's edge.
    if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) s = vec4(0.0);
    if (shadow != 0u) s = vec4(tint.rgb, 1.0) * tint.a * s.a;
    s *= opacity * clip_coverage(clip, gl_FragCoord.xy);
    if (blend < BLEND_SCREEN) {
        result = blend_out(s, blend);
        return;
    }
    vec4 d = textureLod(backdrop, gl_FragCoord.xy / size, 0.0);
    if (blend == BLEND_ERASE) {         // the backdrop where the layer is not
        result = d * (1.0 - s.a);
        return;
    }
    if (blend == BLEND_KEEP) {          // the backdrop where the layer is
        result = d * s.a;
        return;
    }
    vec3 cs = s.a > 0.0 ? s.rgb / s.a : vec3(0.0);
    vec3 cb = d.a > 0.0 ? d.rgb / d.a : vec3(0.0);
    vec3 mixed = (1.0 - d.a) * s.rgb + (1.0 - s.a) * d.rgb + s.a * d.a * blend_fn(blend, cb, cs);
    result = vec4(mixed, s.a + d.a - s.a * d.a);
}
