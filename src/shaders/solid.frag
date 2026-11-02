// The interior of a large plain rectangle (gfx2d.goose's BATCH_SOLIDS):
// fully covered, so its color alone, what shape.frag would work out there.
// It takes shape.vert's outputs as shape.frag does, but reads only the
// color: each value read costs every pixel.
#include "shape.glsl"
#include "paint.glsl"

layout(location = 0) in vec2 v_local;
layout(location = 1) flat in uint v_kind;
layout(location = 2) flat in uint v_flags;
layout(location = 3) flat in vec4 v_geom;
layout(location = 4) flat in vec4 v_radii;
layout(location = 5) flat in vec4 v_color;
layout(location = 6) in vec2 v_user;
layout(location = 7) flat in uint v_paint;
layout(location = 8) flat in uint v_clip;
layout(location = 9) flat in float v_px;
layout(location = 10) flat in vec2 v_sc;

layout(set = 3, binding = 0) uniform Blend { uint blend; uint batch_clip; };

layout(location = 0) out vec4 result;

void main() {
    result = blend_out(vec4(v_color.rgb * v_color.a, v_color.a), blend);
}
