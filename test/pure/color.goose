// gfx2d's colors without a GPU: constructors, conversions there and back,
// and the manipulations, printed as 0xAARRGGBB so the output is exact.
import std;
import gfx2d from "../..";

fn hex32(c: gfx2d::Color) -> u8[>..] {
    let v = gfx2d::to_u32(c);
    var s: u8[>..] = [];
    s.append("0x");
    var shift = 28;
    while shift >= 0 {
        s.push("0123456789ABCDEF"[((v >> shift as u32) & 15) as i64]);
        shift -= 4;
    }
    s
}

fn near(a: f32, b: f32) -> bool { abs(a - b) < 0.002 }

fn same(a: gfx2d::Color, b: gfx2d::Color) -> bool {
    near(a.r, b.r) && near(a.g, b.g) && near(a.b, b.b) && near(a.a, b.a)
}

fn main() {
    print("rgb: ", hex32(gfx2d::rgb(0x336699)), " ", hex32(gfx2d::rgba(0x336699, 0.5)),
          " ", hex32(gfx2d::rgba8(1, 2, 3, 4)), " ", hex32(gfx2d::from_u32(0x80112233)));
    for s in ["#fff", "#0F08", "336699", "#33669980", "#12345", "#ggg"] {
        let c, ok = gfx2d::hex(s);
        print("hex ", s, ": ", ok, " ", hex32(c));
    }

    // Round trips through every space, over a grid of colors.
    var bad = 0;
    var n = 0;
    for r in 5 { for g in 5 { for b in 5 {
        let c = gfx2d::rgbf(r / 4.0, g / 4.0, b / 4.0);
        let v = gfx2d::to_hsv(c);
        let l = gfx2d::to_hsl(c);
        let lab = gfx2d::to_oklab(c);
        let lch = gfx2d::to_oklch(c);
        if !same(c, gfx2d::hsv(v.x, v.y, v.z)) { bad++; print("hsv ", hex32(c)); }
        if !same(c, gfx2d::hsl(l.x, l.y, l.z)) { bad++; print("hsl ", hex32(c)); }
        if !same(c, gfx2d::from_oklab(lab)) { bad++; print("oklab ", hex32(c)); }
        if !same(c, gfx2d::oklch(lch.x, lch.y, lch.z)) { bad++; print("oklch ", hex32(c)); }
        if !same(c, gfx2d::from_linear(gfx2d::to_linear(c))) { bad++; print("linear ", hex32(c)); }
        n++;
    } } }
    print("round trips: ", n, " colors, ", bad, " off");

    print("hsv: ", hex32(gfx2d::hsv(0.0, 1.0, 1.0)), " ", hex32(gfx2d::hsv(1.0 / 3.0, 1.0, 1.0)),
          " ", hex32(gfx2d::hsv(2.0 / 3.0, 1.0, 0.5)), " ", hex32(gfx2d::hsl(1.0 / 6.0, 1.0, 0.5)));
    let white = gfx2d::to_oklab(gfx2d::WHITE);
    print("oklab white: L ", near(white.x, 1.0), ", a ", near(white.y, 0.0), ", b ", near(white.z, 0.0));

    print("mix: ", hex32(gfx2d::mix_srgb(gfx2d::BLACK, gfx2d::WHITE, 0.5)), " ",
          hex32(gfx2d::mix_linear(gfx2d::BLACK, gfx2d::WHITE, 0.5)), " ",
          hex32(gfx2d::mix(gfx2d::RED, gfx2d::BLUE, 0.0)), " ",
          hex32(gfx2d::mix(gfx2d::RED, gfx2d::BLUE, 1.0)), " ",
          hex32(gfx2d::mix_srgb(gfx2d::TRANSPARENT, gfx2d::RED, 0.5)));
    print("over: ", hex32(gfx2d::blend_over(gfx2d::BLUE, gfx2d::rgba(0xFF0000, 0.5))));
    print("luminance: ", near(gfx2d::luminance(gfx2d::WHITE), 1.0), " ",
          near(gfx2d::contrast_ratio(gfx2d::BLACK, gfx2d::WHITE), 21.0), " ",
          hex32(gfx2d::readable_on(gfx2d::NAVY)), " ", hex32(gfx2d::readable_on(gfx2d::YELLOW)));
    let base = gfx2d::rgb(0x3366CC);
    let lighter = gfx2d::lighten(base, 0.1);
    print("lighten: ", near(gfx2d::to_oklch(lighter).x, gfx2d::to_oklch(base).x + 0.1), " ",
          same(gfx2d::darken(lighter, 0.1), base), " hue kept ",
          near(gfx2d::to_oklch(lighter).z, gfx2d::to_oklch(base).z));
    print("rotate_hue full turn: ", same(gfx2d::rotate_hue(base, 1.0), base));
    print("desaturate fully: ", hex32(gfx2d::desaturate(gfx2d::rgb(0x808080), 1.0)), " gray ",
          hex32(gfx2d::grayscale(gfx2d::WHITE)), " invert ", hex32(gfx2d::invert(base)));
    let p = gfx2d::palette(4, 0.0);
    print("palette: ", p.len, " ", hex32(p[0]), " ", hex32(p[1]));
}
