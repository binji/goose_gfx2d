// What shape.vert and shape.frag share: one shape instance, as gfx2d.goose's
// Instance lays it out (std430: 80 bytes), and the shape kinds and flags.
//
// Every shape is drawn in its own local space, centered on the origin; m
// and t take local space to pixels. geom and radii mean, by kind:
//
//   KIND_RECT     geom.xy half extents; radii the corner radii, top left,
//                 top right, bottom right, bottom left
//   KIND_ELLIPSE  geom.xy the radii
//   KIND_PIE      geom.x radius, geom.y half the angle it spans, about +y
//   KIND_ARC      as a pie, and geom.w half the arc's width; round caps
//   KIND_ARC_BUTT the same, with butt caps
//
// geom.z is a stroke's width, with FLAG_STROKE: the outline of the shape,
// centered on its edge, rather than the shape.

struct Instance {
    vec4 m;         // a, b, c, d
    vec2 t;         // tx, ty
    uint kind;
    uint flags;
    vec4 geom;
    vec4 radii;
    vec4 color;     // sRGB, straight alpha
};

const uint KIND_RECT = 0u;
const uint KIND_ELLIPSE = 1u;
const uint KIND_PIE = 2u;
const uint KIND_ARC = 3u;
const uint KIND_ARC_BUTT = 4u;

const uint FLAG_STROKE = 1u;
