// One direction of a separable gaussian blur of `src`, a texture of the
// target's size, into the target: sigma 0 copies it. A copy into a target
// `scale` times smaller each way (2, 4, ...) is a box downsample: each
// target texel the mean of scale by scale source texels.
layout(set = 2, binding = 0) uniform sampler2D src;
layout(set = 3, binding = 0) uniform Blur { vec2 dir; float sigma; float scale; };

layout(location = 0) out vec4 result;

void main() {
    vec2 size = vec2(textureSize(src, 0));
    vec2 uv = gl_FragCoord.xy / size;
    if (sigma <= 0.0) {
        // A grid of (scale / 2)^2 taps over the target texel's box in the
        // source, each between four texels (linear filtering): their mean.
        // Scale 1: one tap, the texel.
        int n = max(int(scale) / 2, 1);
        vec2 base = gl_FragCoord.xy * scale + float(1 - n);
        vec4 sum = vec4(0.0);
        for (int j = 0; j < n; j++) {
            for (int k = 0; k < n; k++) {
                sum += textureLod(src, (base + 2.0 * vec2(j, k)) / size, 0.0);
            }
        }
        result = sum / float(n * n);
        return;
    }
    // Taps two texels apart, each between a pair, by linear filtering: half
    // the taps of one per texel.
    int radius = int(min(ceil(sigma * 3.0), 96.0));
    vec2 step = dir / size;
    vec4 sum = textureLod(src, uv, 0.0);
    float total = 1.0;
    for (int i = 1; i <= radius; i += 2) {
        float w0 = exp(-float(i * i) / (2.0 * sigma * sigma));
        float w1 = exp(-float((i + 1) * (i + 1)) / (2.0 * sigma * sigma));
        float w = w0 + w1;
        float o = (float(i) * w0 + float(i + 1) * w1) / w;
        sum += (textureLod(src, uv + step * o, 0.0) + textureLod(src, uv - step * o, 0.0)) * w;
        total += 2.0 * w;
    }
    result = sum / total;
}
