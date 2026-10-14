// The shape pipeline's fragment shader: the shape's signed distance at this
// pixel (negative inside, in local units), turned into coverage over about
// one pixel, whatever the transform, times the paint's color. The output
// suits the batch's blend mode (Frame.blend). The distance functions are
// Inigo Quilez's.
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

layout(set = 2, binding = 0) uniform sampler2D ramp;
layout(set = 2, binding = 1) uniform sampler2D image;
layout(std430, set = 2, binding = 2) readonly buffer Paints { Paint paints[]; };
layout(set = 3, binding = 0) uniform Blend { uint blend; };

layout(location = 0) out vec4 result;

// A box of half extents b with corner radii r (top left, top right, bottom
// right, bottom left; y is down).
float sd_rounded_box(vec2 p, vec2 b, vec4 r) {
    float radius = p.x > 0.0 ? (p.y > 0.0 ? r.z : r.y) : (p.y > 0.0 ? r.w : r.x);
    vec2 q = abs(p) - b + radius;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
}

// An ellipse of radii ab: exact for a circle, else a first-order
// approximation, good within the antialiased band.
float sd_ellipse(vec2 p, vec2 ab) {
    if (abs(ab.x - ab.y) < 1e-4) return length(p) - ab.x;
    float k1 = length(p / ab);
    float k2 = length(p / (ab * ab));
    return k2 > 0.0 ? k1 * (k1 - 1.0) / k2 : -min(ab.x, ab.y);
}

// A circular sector of radius r about +y, sc the sine and cosine of half
// the angle it spans.
float sd_pie(vec2 p, vec2 sc, float r) {
    p.x = abs(p.x);
    float l = length(p) - r;
    float m = length(p - sc * clamp(dot(p, sc), 0.0, r));
    return max(l, m * sign(sc.y * p.x - sc.x * p.y));
}

// An arc of radius ra and half width rb about +y, with round caps.
float sd_arc(vec2 p, vec2 sc, float ra, float rb) {
    p.x = abs(p.x);
    return ((sc.y * p.x > sc.x * p.y) ? length(p - sc * ra) : abs(length(p) - ra)) - rb;
}

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

    // The paint is read in every fragment, uniformly, so the derivatives
    // the image's sampling takes stay defined.
    vec4 c = paint_color(paints[v_paint], v_color, v_user, gl_FragCoord.xy, ramp, image) * coverage;
    result = blend_out(c, blend);
}
