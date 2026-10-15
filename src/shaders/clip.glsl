// Clips, as gfx2d.goose's ClipGPU lays them out (std430: 64 bytes), and the
// coverage of the chain of clips a fragment is drawn under
// (clip_coverage.glsl, included after the clips[] storage buffer and the
// mask sampler are declared).
//
// Clip 0 is none. Each clip is a rounded box or an ellipse, in a space of
// its own that m and t take pixels to, or a mask texture of the target's
// size, whose red channel is the coverage; its parent clip applies too
// (a mask's already has its parents in it, and its parent is 0).

struct Clip {
    vec4 m;         // pixels to the clip's local space: a, b, c, d
    vec2 t;
    uint kind;
    uint parent;
    vec4 geom;      // half extents (rounded box, ellipse); the mask's size
    vec4 radii;     // a rounded box's corner radii
};

const uint CLIP_NONE = 0u;
const uint CLIP_BOX = 1u;
const uint CLIP_ELLIPSE = 2u;
const uint CLIP_MASK = 3u;
