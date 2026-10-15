// The mesh pipeline's fragment shader: the paint, its tint's alpha carrying
// the coverage the tessellation gave the vertices (1 inside, falling to 0
// across the fringe), out as the batch's blend mode wants it.
#include "paint.glsl"
#include "sdf.glsl"
#include "clip.glsl"

layout(location = 0) in vec2 v_user;
layout(location = 1) in vec4 v_color;
layout(location = 2) flat in uint v_paint;

layout(set = 2, binding = 0) uniform sampler2D ramp;
layout(set = 2, binding = 1) uniform sampler2D image;
layout(set = 2, binding = 2) uniform sampler2D mask;
layout(std430, set = 2, binding = 3) readonly buffer Paints { Paint paints[]; };
layout(std430, set = 2, binding = 4) readonly buffer Clips { Clip clips[]; };
layout(set = 3, binding = 0) uniform Blend { uint blend; uint clip; };

layout(location = 0) out vec4 result;

#include "clip_coverage.glsl"

void main() {
    vec4 c;
    if (v_paint == 0u && clip == 0u) {
        // The color alone, unclipped: a flat (per primitive) and a uniform.
        c = vec4(v_color.rgb * v_color.a, v_color.a);
    } else {
        c = paint_color(paints[v_paint], v_color, v_user, gl_FragCoord.xy, ramp, image)
            * clip_coverage(clip, gl_FragCoord.xy);
    }
    result = blend_out(c, blend);
}
