// The coverage of the chain of clips from clip i (clip.glsl) at a pixel. The
// including shader declares sdf.glsl's functions, the clips[] storage
// buffer and the mask sampler first.

float clip_coverage(uint i, vec2 pixel) {
    float c = 1.0;
    for (int n = 0; n < 16 && i != 0u; n++) {
        Clip k = clips[i];
        if (k.kind == CLIP_MASK) {
            c *= textureLod(mask, pixel / k.geom.xy, 0.0).r;
        } else {
            vec2 p = k.m.xy * pixel.x + k.m.zw * pixel.y + k.t;
            float d = k.kind == CLIP_ELLIPSE ? sd_ellipse(p, k.geom.xy)
                                             : sd_rounded_box(p, k.geom.xy, k.radii);
            // A pixel in the clip's units, from the transform's scale.
            float px = sqrt(max(abs(k.m.x * k.m.w - k.m.y * k.m.z), 1e-12));
            c *= clamp(0.5 - d / px, 0.0, 1.0);
        }
        i = k.parent;
    }
    return c;
}
