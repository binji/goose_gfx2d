// The shape pipeline's fragment shader: the shape's signed distance at this
// pixel (negative inside, in local units), turned into coverage over about
// one pixel, whatever the transform. Output is premultiplied, for
// gfx::BLEND_PREMULTIPLIED. The distance functions are Inigo Quilez's.
#include "shape.glsl"

layout(location = 0) in vec2 v_local;
layout(location = 1) flat in uint v_kind;
layout(location = 2) flat in uint v_flags;
layout(location = 3) flat in vec4 v_geom;
layout(location = 4) flat in vec4 v_radii;
layout(location = 5) flat in vec4 v_color;

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
    vec2 sc = vec2(sin(v_geom.y), cos(v_geom.y));
    float d;
    if (v_kind == KIND_RECT) {
        d = sd_rounded_box(p, v_geom.xy, v_radii);
    } else if (v_kind == KIND_ELLIPSE) {
        d = sd_ellipse(p, v_geom.xy);
    } else if (v_kind == KIND_PIE) {
        d = sd_pie(p, sc, v_geom.x);
    } else if (v_kind == KIND_ARC) {
        d = sd_arc(p, sc, v_geom.x, v_geom.w);
    } else {
        d = max(abs(length(p) - v_geom.x) - v_geom.w, sd_pie(p, sc, v_geom.x + v_geom.w + 1.0));
    }

    // One pixel in local units: the local distance a step to the next pixel
    // covers, averaged over x and y, so rotation leaves it alone.
    float px = max(0.5 * (length(dFdx(p)) + length(dFdy(p))), 1e-6);
    float alpha = v_color.a;
    if ((v_flags & FLAG_STROKE) != 0u) {
        // A stroke thinner than a pixel is drawn a pixel wide, as faint as
        // it is thin, so it neither vanishes nor flickers as it moves.
        float width = v_geom.z;
        alpha *= min(width / px, 1.0);
        d = abs(d) - max(width, px) * 0.5;
    }
    float coverage = clamp(0.5 - d / px, 0.0, 1.0);
    float a = alpha * coverage;
    result = vec4(v_color.rgb * a, a);
}
