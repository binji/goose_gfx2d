// The shape pipeline's vertex shader: six vertices per instance, no vertex
// buffer. Each instance is a quad around its shape, grown by a pixel and a
// half for the edge's antialiasing, in local space; the fragment shader gets
// the local position and decides coverage. A large plain rectangle is drawn
// as two pieces instead (Frame.mode): the quad less its interior, 24
// vertices, by shape.frag, and the interior, six, by solid.frag.
#include "shape.glsl"

layout(std430, set = 0, binding = 0) readonly buffer Instances { Instance inst[]; };
// view: the target's size in pixels. base: this batch's first instance (an
// offset of our own, since backends disagree on whether gl_VertexIndex
// counts a draw's first vertex).
layout(set = 1, binding = 0) uniform Frame { vec4 view; uint base; uint mode; };

layout(location = 0) out vec2 v_local;
layout(location = 1) flat out uint v_kind;
layout(location = 2) flat out uint v_flags;
layout(location = 3) flat out vec4 v_geom;
layout(location = 4) flat out vec4 v_radii;
layout(location = 5) flat out vec4 v_color;
layout(location = 6) out vec2 v_user;
layout(location = 7) flat out uint v_paint;
layout(location = 8) flat out uint v_clip;
layout(location = 9) flat out float v_px;      // one pixel in local units
layout(location = 10) flat out vec2 v_sc;      // the sine and cosine of a sector's half angle

const vec2 corners[6] = vec2[6](vec2(-1.0, -1.0), vec2(1.0, -1.0), vec2(1.0, 1.0),
                                vec2(-1.0, -1.0), vec2(1.0, 1.0), vec2(-1.0, 1.0));

// gfx2d.goose's SHAPE_*: the quad, the ring (the quad less the interior) or
// the interior.
const uint SHAPE_QUAD = 0u;
const uint SHAPE_RING = 1u;
const uint SHAPE_INTERIOR = 2u;
// The ring: a strip along each side, between the quad's corners (outer) and
// the interior's, two triangles each, as a corner (0 to 3 around) and
// whether it is the interior's.
const vec2 around[4] = vec2[4](vec2(-1.0, -1.0), vec2(1.0, -1.0), vec2(1.0, 1.0), vec2(-1.0, 1.0));
const uint ring_corner[24] = uint[24](0u, 1u, 1u, 0u, 1u, 0u,  1u, 2u, 2u, 1u, 2u, 1u,
                                      2u, 3u, 3u, 2u, 3u, 2u,  3u, 0u, 0u, 3u, 0u, 3u);
const uint ring_inner[24] = uint[24](0u, 0u, 1u, 0u, 1u, 1u,  0u, 0u, 1u, 0u, 1u, 1u,
                                     0u, 0u, 1u, 0u, 1u, 1u,  0u, 0u, 1u, 0u, 1u, 1u);

void main() {
    uint per = mode == SHAPE_RING ? 24u : 6u;
    uint vertex_index = uint(gl_VertexIndex) % per;
    Instance s = inst[base + uint(gl_VertexIndex) / per];
    vec2 extent;
    if (s.kind == KIND_RECT || s.kind == KIND_ELLIPSE || s.kind == KIND_GLYPH) {
        extent = s.geom.xy;
    } else if (s.kind == KIND_PIE) {
        extent = vec2(s.geom.x);
    } else {
        extent = vec2(s.geom.x + s.geom.w);
    }
    if ((s.flags & FLAG_STROKE) != 0u) extent += vec2(s.geom.z * 0.5);
    if (s.kind == KIND_SHADOW) extent = s.geom.xy + 3.0 * s.geom.z;
    // A pixel and a half in local units, along each local axis.
    vec2 scales = vec2(length(s.m.xy), length(s.m.zw));
    extent += 1.5 / max(scales, vec2(1e-6));

    // One pixel in local units: how far in local space a step to the next
    // pixel goes, along x and along y, averaged, so rotation leaves it
    // alone. The transform is affine, so it is the same over the quad, and
    // the fragment shader need not take derivatives for it.
    float det = s.m.x * s.m.w - s.m.y * s.m.z;
    float px = max(0.5 * (length(vec2(s.m.w, -s.m.y)) + length(vec2(-s.m.z, s.m.x))) / max(abs(det), 1e-12), 1e-6);
    // The interior (gfx2d.goose's has_interior): fully covered, a pixel or
    // more inside the corners' reach.
    float r = max(max(s.radii.x, s.radii.y), max(s.radii.z, s.radii.w));
    vec2 inner = max(s.geom.xy - r - px, vec2(0.0));
    vec2 p;
    if (mode == SHAPE_RING) {
        p = around[ring_corner[vertex_index]] * (ring_inner[vertex_index] != 0u ? inner : extent);
    } else if (mode == SHAPE_INTERIOR) {
        p = corners[vertex_index] * inner;
    } else {
        p = corners[vertex_index] * extent;
    }
    vec2 pixel = s.m.xy * p.x + s.m.zw * p.y + s.t;
    gl_Position = vec4(pixel.x / view.x * 2.0 - 1.0, 1.0 - pixel.y / view.y * 2.0, 0.0, 1.0);

    v_local = p;
    v_kind = s.kind;
    v_flags = s.flags;
    v_geom = s.geom;
    v_radii = s.radii;
    v_color = s.color;
    v_user = s.lm.xy * p.x + s.lm.zw * p.y + s.lt;
    v_paint = s.paint;
    v_clip = s.clip;
    v_px = px;
    v_sc = vec2(sin(s.geom.y), cos(s.geom.y));
}
