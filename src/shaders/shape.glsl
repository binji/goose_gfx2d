// What shape.vert and shape.frag share: one shape instance, as gfx2d.goose's
// Instance lays it out (std430: 112 bytes), and the shape kinds and flags.
//
// Every shape is drawn in its own local space, centered on the origin; m
// and t take local space to pixels, lm and lt to the space it was drawn in
// (under the current transform), where its paint is. geom and radii mean,
// by kind:
//
//   KIND_RECT     geom.xy half extents; radii the corner radii, top left,
//                 top right, bottom right, bottom left
//   KIND_ELLIPSE  geom.xy the radii
//   KIND_PIE      geom.x radius, geom.y half the angle it spans, about +y
//   KIND_ARC      as a pie, and geom.w half the arc's width; round caps
//   KIND_ARC_BUTT the same, with butt caps
//   KIND_SHADOW   a rounded box blurred: geom.xy half extents, geom.z the
//                 blur's sigma, radii.x the corner radius
//   KIND_GLYPH    a glyph of the atlas: geom.xy half its size; radii its
//                 place in the atlas, x, y, w, h, in the atlas's pixels,
//                 which local space is in
//
// geom.z is a stroke's width, with FLAG_STROKE: the outline of the shape,
// centered on its edge, rather than the shape.
//
// A rectangle's FLAG_HARD_* sides are not antialiased: a pixel is in by
// whether its center is, half-open (the left and top sides in, the right
// and bottom out), so rectangles meeting there (a nine-slice's pieces,
// tiles) cover every pixel once, with no seam.

struct Instance {
    vec4 m;         // a, b, c, d
    vec2 t;         // tx, ty
    uint kind;
    uint flags;
    vec4 geom;
    vec4 radii;
    vec4 color;     // sRGB, straight alpha: the source, or a paint's tint
    vec4 lm;        // local space to the paint's
    vec2 lt;
    uint paint;     // the paint's index in paints[]; 0: the color alone
    uint clip;      // the clip's index in clips[]; 0: none
};

const uint KIND_RECT = 0u;
const uint KIND_ELLIPSE = 1u;
const uint KIND_PIE = 2u;
const uint KIND_ARC = 3u;
const uint KIND_ARC_BUTT = 4u;
const uint KIND_GLYPH = 5u;
const uint KIND_SHADOW = 6u;

const uint FLAG_STROKE = 1u;
const uint FLAG_HARD_LEFT = 2u;
const uint FLAG_HARD_TOP = 4u;
const uint FLAG_HARD_RIGHT = 8u;
const uint FLAG_HARD_BOTTOM = 16u;
const uint FLAG_ALIASED = 32u;
