// The shape pipeline's vertex shader: six vertices per instance, no vertex
// buffer. Each instance is a quad around its shape, grown by a pixel and a
// half for the edge's antialiasing, in local space; the fragment shader gets
// the local position and decides coverage.
#include "shape.glsl"

layout(std430, set = 0, binding = 0) readonly buffer Instances { Instance inst[]; };
// view: the target's size in pixels. base: this batch's first instance (an
// offset of our own, since backends disagree on whether gl_VertexIndex
// counts a draw's first vertex).
layout(set = 1, binding = 0) uniform Frame { vec4 view; uint base; };

layout(location = 0) out vec2 v_local;
layout(location = 1) flat out uint v_kind;
layout(location = 2) flat out uint v_flags;
layout(location = 3) flat out vec4 v_geom;
layout(location = 4) flat out vec4 v_radii;
layout(location = 5) flat out vec4 v_color;

const vec2 corners[6] = vec2[6](vec2(-1.0, -1.0), vec2(1.0, -1.0), vec2(1.0, 1.0),
                                vec2(-1.0, -1.0), vec2(1.0, 1.0), vec2(-1.0, 1.0));

void main() {
    Instance s = inst[base + uint(gl_VertexIndex) / 6u];
    vec2 extent;
    if (s.kind == KIND_RECT || s.kind == KIND_ELLIPSE) {
        extent = s.geom.xy;
    } else if (s.kind == KIND_PIE) {
        extent = vec2(s.geom.x);
    } else {
        extent = vec2(s.geom.x + s.geom.w);
    }
    if ((s.flags & FLAG_STROKE) != 0u) extent += vec2(s.geom.z * 0.5);
    // A pixel and a half in local units, along each local axis.
    vec2 scales = vec2(length(s.m.xy), length(s.m.zw));
    extent += 1.5 / max(scales, vec2(1e-6));

    vec2 p = corners[uint(gl_VertexIndex) % 6u] * extent;
    vec2 pixel = s.m.xy * p.x + s.m.zw * p.y + s.t;
    gl_Position = vec4(pixel.x / view.x * 2.0 - 1.0, 1.0 - pixel.y / view.y * 2.0, 0.0, 1.0);

    v_local = p;
    v_kind = s.kind;
    v_flags = s.flags;
    v_geom = s.geom;
    v_radii = s.radii;
    v_color = s.color;
}
