// The mesh pipeline's fragment shader: the paint, times the coverage the
// tessellation gave the vertices (1 inside, falling to 0 across the
// fringe), out as the batch's blend mode wants it.
#include "paint.glsl"

layout(location = 0) in vec2 v_user;
layout(location = 1) flat in vec4 v_color;
layout(location = 2) in float v_alpha;
layout(location = 3) flat in uint v_paint;

layout(set = 2, binding = 0) uniform sampler2D ramp;
layout(set = 2, binding = 1) uniform sampler2D image;
layout(std430, set = 2, binding = 2) readonly buffer Paints { Paint paints[]; };
layout(set = 3, binding = 0) uniform Blend { uint blend; };

layout(location = 0) out vec4 result;

void main() {
    vec4 c = paint_color(paints[v_paint], v_color, v_user, gl_FragCoord.xy, ramp, image);
    result = blend_out(c * clamp(v_alpha, 0.0, 1.0), blend);
}
