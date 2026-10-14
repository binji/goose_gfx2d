// A paint, as gfx2d.goose's PaintGPU lays it out (std430: 96 bytes), and
// how a fragment is painted with one. The constants are paint.goose's.

struct Paint {
    uint kind;          // GRADIENT_*: 0, the instance's color alone
    uint spread;        // SPREAD_*
    uint image_mode;    // IMAGE_*, or IMAGE_NONE
    uint flags;         // PAINT_SCREEN, and the image's WRAP_* << 4
    vec4 g0;            // linear: p0, p1; radial: center, focal point; conic: center, angle
    vec4 g1;            // radial: radius; z: the ramp's row; w: opacity
    vec4 im;            // the paint's space to the image's pixels: a, b, c, d
    vec4 it;            // tx, ty; z: 1 for a part of the texture
    vec4 src;           // that part, in pixels
};

const uint GRADIENT_NONE = 0u;
const uint GRADIENT_LINEAR = 1u;
const uint GRADIENT_RADIAL = 2u;
const uint GRADIENT_CONIC = 3u;
const uint SPREAD_PAD = 0u;
const uint SPREAD_REPEAT = 1u;
const uint SPREAD_REFLECT = 2u;
const uint IMAGE_MULTIPLY = 0u;
const uint IMAGE_REPLACE = 1u;
const uint IMAGE_ADD = 2u;
const uint IMAGE_MASK = 3u;
const uint IMAGE_NONE = 255u;
const uint WRAP_CLAMP = 0u;
const uint WRAP_REPEAT = 1u;
const uint WRAP_MIRROR = 2u;
const uint WRAP_DECAL = 3u;
const uint PAINT_SCREEN = 1u;

const float TAU = 6.283185307179586;

// Where along the gradient p is, before spreading.
float gradient_t(Paint g, vec2 p) {
    if (g.kind == GRADIENT_LINEAR) {
        vec2 d = g.g0.zw - g.g0.xy;
        float len2 = dot(d, d);
        return len2 > 0.0 ? dot(p - g.g0.xy, d) / len2 : 0.0;
    }
    if (g.kind == GRADIENT_RADIAL) {
        // Circles from the focal point f, radius 0, to the center c, radius
        // r: the t whose circle p lies on, |q - t d| = t r.
        float r = g.g1.x;
        vec2 f = g.g0.zw;
        vec2 d = g.g0.xy - f;
        vec2 q = p - f;
        float a = dot(d, d) - r * r;
        float b = dot(q, d);
        float qq = dot(q, q);
        if (abs(a) < 1e-6) return b > 0.0 ? qq / (2.0 * b) : 0.0;
        return (b - sqrt(max(b * b - a * qq, 0.0))) / a;
    }
    // Conic: clockwise from the angle, y being down.
    vec2 q = p - g.g0.xy;
    return fract((atan(q.y, q.x) - g.g0.z) / TAU);
}

float spread(uint mode, float t) {
    if (mode == SPREAD_REPEAT) return fract(t);
    if (mode == SPREAD_REFLECT) return 1.0 - abs(mod(t, 2.0) - 1.0);
    return clamp(t, 0.0, 1.0);
}

// The texture's color at p, the paint's space, premultiplied. A whole
// texture wraps by its sampler; a part of one wraps here, inset half a
// texel, so its neighbors in the texture never bleed in.
vec4 image_at(Paint g, vec2 p, sampler2D image) {
    vec2 size = vec2(textureSize(image, 0));
    vec2 ip = g.im.xy * p.x + g.im.zw * p.y + g.it.xy;
    bool part = g.it.z > 0.0;
    vec4 src = part ? g.src : vec4(0.0, 0.0, size);
    vec2 t = ip / src.zw;
    uint wrap = (g.flags >> 4) & 3u;
    if (wrap == WRAP_DECAL && (any(lessThan(t, vec2(0.0))) || any(greaterThan(t, vec2(1.0))))) {
        return vec4(0.0);
    }
    // Gradients for the mip level come from the unwrapped position, so a
    // wrapped seam is not a jump to the smallest mip.
    vec2 uv_raw = (src.xy + t * src.zw) / size;
    vec2 dx = dFdx(uv_raw);
    vec2 dy = dFdy(uv_raw);
    if (part) {
        if (wrap == WRAP_REPEAT) t = fract(t);
        else if (wrap == WRAP_MIRROR) t = 1.0 - abs(mod(t, 2.0) - 1.0);
        vec2 inset = 0.5 / src.zw;
        t = clamp(t, inset, 1.0 - inset);
    }
    vec4 c = textureGrad(image, (src.xy + t * src.zw) / size, dx, dy);
    return vec4(c.rgb * c.a, c.a);
}

// The painted color, premultiplied, before coverage. `user` is the point in
// the space the shape was drawn in, `pixel` in the target.
vec4 paint_color(Paint g, vec4 tint, vec2 user, vec2 pixel, sampler2D ramp, sampler2D image) {
    vec2 p = (g.flags & PAINT_SCREEN) != 0u ? pixel : user;
    vec4 c = vec4(tint.rgb * tint.a, tint.a);
    if (g.kind != GRADIENT_NONE) {
        float t = spread(g.spread, gradient_t(g, p));
        vec2 rsize = vec2(textureSize(ramp, 0));
        vec2 uv = vec2((t * (rsize.x - 1.0) + 0.5) / rsize.x, (g.g1.z + 0.5) / rsize.y);
        c *= textureLod(ramp, uv, 0.0);
    }
    if (g.image_mode != IMAGE_NONE) {
        vec4 img = image_at(g, p, image);
        if (g.image_mode == IMAGE_MULTIPLY) c *= img;
        else if (g.image_mode == IMAGE_REPLACE) c = img;
        else if (g.image_mode == IMAGE_ADD) c = vec4(min(c.rgb + img.rgb, vec3(1.0)), max(c.a, img.a));
        else c *= img.a;
    }
    return c * g.g1.w;
}
