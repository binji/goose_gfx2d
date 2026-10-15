// gfx2d's paints without a GPU: gradients' colors along t, as the ramps
// the GPU samples hold them, and the builders.
import std;
import gfx2d from "../..";

fn bytes(c: gfx2d::Color) -> u8[>..] {
    let v = gfx2d::to_u32(c);
    str((v >> 16) & 255, ",", (v >> 8) & 255, ",", v & 255, ",", v >> 24)
}

fn main() {
    let bw = gfx2d::linear_gradient(0, 0, 100, 0, [gfx2d::stop(0.2, gfx2d::BLACK),
                                                   gfx2d::stop(0.8, gfx2d::WHITE)]);
    print("kind ", bw.kind, ", ", bw.stops.len, " stops, from ", bw.p0, " to ", bw.p1);
    print("before, first, middle, last, after: ", bytes(gfx2d::gradient_at(bw, 0.0)), " ",
          bytes(gfx2d::gradient_at(bw, 0.2)), " ", bytes(gfx2d::gradient_at(bw, 0.5)), " ",
          bytes(gfx2d::gradient_at(bw, 0.8)), " ", bytes(gfx2d::gradient_at(bw, 1.0)));

    // The middle of red to blue in each space.
    var g = gfx2d::linear_gradient(0, 0, 1, 0, [gfx2d::stop(0, gfx2d::RED), gfx2d::stop(1, gfx2d::BLUE)]);
    print("srgb middle: ", bytes(gfx2d::gradient_at(g, 0.5)));
    g.space = gfx2d::INTERPOLATE_LINEAR;
    print("linear middle: ", bytes(gfx2d::gradient_at(g, 0.5)));
    g.space = gfx2d::INTERPOLATE_OKLAB;
    print("oklab middle: ", bytes(gfx2d::gradient_at(g, 0.5)));

    // A stop below the one before it counts as that one: a hard edge.
    let hard = gfx2d::linear_gradient(0, 0, 1, 0, [gfx2d::stop(0, gfx2d::RED), gfx2d::stop(0.5, gfx2d::RED),
                                                   gfx2d::stop(0.1, gfx2d::BLUE), gfx2d::stop(1, gfx2d::BLUE)]);
    print("hard edge: ", bytes(gfx2d::gradient_at(hard, 0.49)), " ", bytes(gfx2d::gradient_at(hard, 0.51)));
    // To transparent, premultiplied: the middle is half-transparent red,
    // not a darkened one.
    let fade = gfx2d::linear_gradient(0, 0, 1, 0, [gfx2d::stop(0, gfx2d::RED),
                                                   gfx2d::stop(1, gfx2d::TRANSPARENT)]);
    print("to transparent: ", bytes(gfx2d::gradient_at(fade, 0.5)));
    let none = gfx2d::linear_gradient(0, 0, 1, 0, []);
    let one = gfx2d::radial_gradient(0, 0, 1, [gfx2d::stop(0.5, gfx2d::LIME)]);
    print("no stops: ", bytes(gfx2d::gradient_at(none, 0.5)), ", one stop: ",
          bytes(gfx2d::gradient_at(one, 0.0)), " ", bytes(gfx2d::gradient_at(one, 1.0)));

    // At most MAX_STOPS stops.
    var many: gfx2d::Stop[>..] = [];
    for i in 20 { many.push(gfx2d::stop(i / 19.0, gfx2d::gray(i / 19.0))); }
    print("stops kept: ", gfx2d::conic_gradient(0, 0, 0, many).stops.len);

    // A ramp: 256 premultiplied RGBA8 texels, from the first color to the last.
    var ramp: u8[>..<] = [];
    gfx2d::append_ramp(fade, ramp);
    print("ramp: ", ramp.len, " bytes, ", ramp[0], ",", ramp[1], ",", ramp[2], ",", ramp[3], " .. ",
          ramp[1020], ",", ramp[1021], ",", ramp[1022], ",", ramp[1023], "; middle alpha ",
          ramp[128 * 4 + 3], " red ", ramp[128 * 4]);
    // The sRGB ramp, baked in one pass, agrees with gradient_at everywhere.
    let varied = gfx2d::linear_gradient(0, 0, 1, 0, [
        gfx2d::stop(0.1, gfx2d::rgba(0x336699, 0.2)), gfx2d::stop(0.3, gfx2d::ORANGE),
        gfx2d::stop(0.3, gfx2d::LIME), gfx2d::stop(0.2, gfx2d::rgba(0xFF00FF, 0.7)),
        gfx2d::stop(0.75, gfx2d::TRANSPARENT), gfx2d::stop(0.9, gfx2d::WHITE)]);
    var fast: u8[>..<] = [];
    gfx2d::append_ramp(varied, fast);
    var worst = 0;
    for i in 256 {
        let c = gfx2d::premultiplied(gfx2d::gradient_at(varied, i / 255.0));
        let want: f32[4] = [c.x, c.y, c.z, c.w];
        for k in 4 {
            let w = (gfx2d::saturate(want[k]) * 255.0 + 0.5) as i64;
            worst = max(worst, abs(w - fast[i * 4 + k]));
        }
    }
    print("one-pass ramp: off by at most ", worst);

    print("same ramp: ", gfx2d::same_ramp(bw, gfx2d::radial_gradient(5, 5, 9, bw.stops[..])), " ",
          gfx2d::same_ramp(bw, g));

    let p = gfx2d::linear(0, 0, 10, 0, gfx2d::RED, gfx2d::BLUE);
    print("linear(): ", p.gradient.kind, " ", p.gradient.stops.len, " opacity ",
          gfx2d::with_opacity(p, 0.5).opacity, " blend ", gfx2d::with_blend(p, gfx2d::BLEND_ADD).blend);
    let r = gfx2d::radial_gradient(10, 20, 30, 12, 22, [gfx2d::stop(0, gfx2d::WHITE)]);
    print("radial: ", r.p0, " focal ", r.p1, " radius ", r.radius);
}
