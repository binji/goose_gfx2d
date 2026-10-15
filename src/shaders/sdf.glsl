// Signed distance functions (negative inside, in the units of p), shared by
// the shapes and the clips; and the blurred rounded box of box_shadow.
// The distance functions are Inigo Quilez's; the shadow Evan Wallace's.

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

// A rounded box blurred by a gaussian of sigma: its coverage at p, the
// box's half extents b and corner radius r, by integrating across x in
// closed form (erf) and along y in four steps.
float gaussian(float x, float sigma) {
    return exp(-(x * x) / (2.0 * sigma * sigma)) / (2.5066282746 * sigma);
}
vec2 erf2(vec2 x) {
    vec2 s = sign(x), a = abs(x);
    x = 1.0 + (0.278393 + (0.230389 + 0.078108 * (a * a)) * a) * a;
    x *= x;
    return s - s / (x * x);
}
float shadow_x(float x, float y, float sigma, float r, vec2 b) {
    float delta = min(b.y - r - abs(y), 0.0);
    float curved = b.x - r + sqrt(max(0.0, r * r - delta * delta));
    vec2 integral = 0.5 + 0.5 * erf2((x + vec2(-curved, curved)) * (0.7071067812 / sigma));
    return integral.y - integral.x;
}
float box_shadow(vec2 p, vec2 b, float r, float sigma) {
    float low = p.y - b.y;
    float high = p.y + b.y;
    float start = clamp(-3.0 * sigma, low, high);
    float end = clamp(3.0 * sigma, low, high);
    float step = (end - start) / 4.0;
    float y = start + step * 0.5;
    float value = 0.0;
    for (int i = 0; i < 4; i++) {
        value += shadow_x(p.x, p.y - y, sigma, r, b) * gaussian(y, sigma) * step;
        y += step;
    }
    return value;
}
