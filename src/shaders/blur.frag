// One direction of a separable gaussian blur of `src`, a texture of the
// target's size, into the target: sigma 0 copies it.
layout(set = 2, binding = 0) uniform sampler2D src;
layout(set = 3, binding = 0) uniform Blur { vec2 dir; float sigma; float pad; };

layout(location = 0) out vec4 result;

void main() {
    vec2 size = vec2(textureSize(src, 0));
    vec2 uv = gl_FragCoord.xy / size;
    if (sigma <= 0.0) {
        result = textureLod(src, uv, 0.0);
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
