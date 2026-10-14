// gfx2d's colors: the Color type, constructors, conversions between sRGB,
// linear light, HSV, HSL, OKLab and OKLCh, and the manipulations built on
// them. Plain Goose: no GPU and no C, so all of it runs and is tested
// headless (test/pure/color.goose).
//
// A Color is sRGB-encoded with straight (not premultiplied) alpha, every
// channel from 0 to 1, as CSS and image files have colors. Hues, in hsv(),
// hsl(), oklch() and rotate_hue(), are in turns: 0 to 1 around the wheel,
// 1/3 green, 2/3 blue. Conversions that leave sRGB's gamut, as an OKLCh
// color of high chroma can, clamp each channel into it.

namespace gfx2d;

import std;
import vec;
import math;

struct Color { r: f32, g: f32, b: f32, a: f32 }

// --- constants: the CSS basic colors, and a few more ---------------------------

let TRANSPARENT = Color { 0.0, 0.0, 0.0, 0.0 };
let BLACK = rgb(0x000000);
let WHITE = rgb(0xFFFFFF);
let SILVER = rgb(0xC0C0C0);
let GRAY = rgb(0x808080);
let MAROON = rgb(0x800000);
let RED = rgb(0xFF0000);
let PURPLE = rgb(0x800080);
let FUCHSIA = rgb(0xFF00FF);
let MAGENTA = rgb(0xFF00FF);
let GREEN = rgb(0x008000);
let LIME = rgb(0x00FF00);
let OLIVE = rgb(0x808000);
let YELLOW = rgb(0xFFFF00);
let NAVY = rgb(0x000080);
let BLUE = rgb(0x0000FF);
let TEAL = rgb(0x008080);
let AQUA = rgb(0x00FFFF);
let CYAN = rgb(0x00FFFF);
let ORANGE = rgb(0xFFA500);

// --- constructors --------------------------------------------------------------

// 0xRRGGBB, opaque; with an alpha from 0 to 1.
fn rgb(hex: i64) -> Color {
    Color { ((hex >> 16) & 255) / 255.0, ((hex >> 8) & 255) / 255.0, (hex & 255) / 255.0, 1.0 }
}
fn rgba(hex: i64, a: f64) -> Color { with_alpha(rgb(hex), a) }
// Channels as bytes, 0 to 255.
fn rgba8(r: i64, g: i64, b: i64, a: i64) -> Color {
    Color { r / 255.0, g / 255.0, b / 255.0, a / 255.0 }
}
// Channels from 0 to 1.
fn rgbf(r: f64, g: f64, b: f64) -> Color { rgbaf(r, g, b, 1.0) }
fn rgbaf(r: f64, g: f64, b: f64, a: f64) -> Color { Color { r as f32, g as f32, b as f32, a as f32 } }
fn gray(v: f64) -> Color { rgbaf(v, v, v, 1.0) }
fn gray(v: f64, a: f64) -> Color { rgbaf(v, v, v, a) }
// 0xAARRGGBB.
fn from_u32(argb: u32) -> Color {
    rgba8((argb >> 16) & 255, (argb >> 8) & 255, argb & 255, (argb >> 24) & 255)
}
fn from_float4(v: float4) -> Color { Color { v.x, v.y, v.z, v.w } }

fn hex_digit(c: u8) -> i64 {
    if c >= '0' && c <= '9' { return c - '0'; }
    if c >= 'a' && c <= 'f' { return c - 'a' + 10; }
    if c >= 'A' && c <= 'F' { return c - 'A' + 10; }
    -1
}

// CSS hex notation: "#rgb", "#rgba", "#rrggbb" or "#rrggbbaa", the '#'
// optional. False, and transparent, for anything else.
fn hex(s: const u8[:]) -> Color, bool {
    var at = if s.len > 0 && s[0] == '#' { 1 } else { 0 };
    let n = s.len - at;
    guard n == 3 || n == 4 || n == 6 || n == 8 else { return TRANSPARENT, false; }
    var v: i64[4] = [0, 0, 0, 255];
    let short = n <= 4;
    for i in (if short { n } else { n / 2 }) {
        var x = 0;
        if short {
            let d = hex_digit(s[at + i]);
            if d < 0 { return TRANSPARENT, false; }
            x = d * 17;
        } else {
            let hi = hex_digit(s[at + 2 * i]);
            let lo = hex_digit(s[at + 2 * i + 1]);
            if hi < 0 || lo < 0 { return TRANSPARENT, false; }
            x = hi * 16 + lo;
        }
        v[i] = x;
    }
    return rgba8(v[0], v[1], v[2], v[3]), true;
}

// --- conversions ---------------------------------------------------------------

fn to_float4(c: Color) -> float4 { float4 { c.r, c.g, c.b, c.a } }
// 0xAARRGGBB, each channel rounded to a byte.
fn to_u32(c: Color) -> u32 {
    (byte(c.a) << 24) | (byte(c.r) << 16) | (byte(c.g) << 8) | byte(c.b)
}
fn byte(x: f32) -> u32 { round(saturate(x) * 255.0) as u32 }
fn saturate(x: f32) -> f32 { if x < 0.0 { 0.0 } else if x > 1.0 { 1.0 } else { x } }

// The color with its channels multiplied by its alpha, as the GPU blends.
fn premultiplied(c: Color) -> float4 { float4 { c.r * c.a, c.g * c.a, c.b * c.a, c.a } }

// One channel between sRGB's encoding and linear light.
fn srgb_to_linear(x: f32) -> f32 {
    if x <= 0.04045 { x / 12.92 } else { pow((x + 0.055) / 1.055, 2.4 as f32) }
}
fn linear_to_srgb(x: f32) -> f32 {
    if x <= 0.0031308 { x * 12.92 } else { 1.055 * pow(x, (1.0 / 2.4) as f32) - 0.055 }
}
// Linear-light RGB, alpha unchanged.
fn to_linear(c: Color) -> float4 {
    float4 { srgb_to_linear(c.r), srgb_to_linear(c.g), srgb_to_linear(c.b), c.a }
}
fn from_linear(v: float4) -> Color {
    Color { saturate(linear_to_srgb(v.x)), saturate(linear_to_srgb(v.y)),
            saturate(linear_to_srgb(v.z)), saturate(v.w) }
}

fn fract(x: f32) -> f32 { x - floor(x) }
fn fract(x: f64) -> f64 { x - floor(x) }

// Scalars are f64 here, as in the rest of gfx2d, so that numbers of any
// type pass; a Color holds f32.

// HSV: hue in turns, saturation and value from 0 to 1.
fn hsv(h: f64, s: f64, v: f64) -> Color { hsva(h, s, v, 1.0) }
fn hsva(h: f64, s: f64, v: f64, a: f64) -> Color {
    let k = fract(h) * 6.0;
    fn channel(n: f64) -> f64 {
        let t = (n + k) % 6.0;
        v - v * s * max(0.0, min(min(t, 4.0 - t), 1.0))
    }
    rgbaf(channel(5.0), channel(3.0), channel(1.0), a)
}
// { h, s, v, a }
fn to_hsv(c: Color) -> float4 {
    let hi = max(max(c.r, c.g), c.b);
    let lo = min(min(c.r, c.g), c.b);
    let d = hi - lo;
    float4 { hue_of(c, hi, d), if hi > 0.0 { d / hi } else { 0.0 }, hi, c.a }
}

// HSL: hue in turns, saturation and lightness from 0 to 1.
fn hsl(h: f64, s: f64, l: f64) -> Color { hsla(h, s, l, 1.0) }
fn hsla(h: f64, s: f64, l: f64, a: f64) -> Color {
    let k = fract(h) * 12.0;
    let m = s * min(l, 1.0 - l);
    fn channel(n: f64) -> f64 {
        let t = (n + k) % 12.0;
        l - m * max(-1.0, min(min(t - 3.0, 9.0 - t), 1.0))
    }
    rgbaf(channel(0.0), channel(8.0), channel(4.0), a)
}
// { h, s, l, a }
fn to_hsl(c: Color) -> float4 {
    let hi = max(max(c.r, c.g), c.b);
    let lo = min(min(c.r, c.g), c.b);
    let d = hi - lo;
    let l = (hi + lo) * 0.5;
    let s = if d == 0.0 { 0.0 } else { d / (1.0 - abs(2.0 * l - 1.0)) };
    float4 { hue_of(c, hi, d), s, l, c.a }
}

// The hue, in turns, of a color whose largest channel is hi and whose
// channels span d.
fn hue_of(c: Color, hi: f32, d: f32) -> f32 {
    if d == 0.0 { return 0.0; }
    let h = if hi == c.r { ((c.g - c.b) / d) % 6.0 }
            else if hi == c.g { (c.b - c.r) / d + 2.0 }
            else { (c.r - c.g) / d + 4.0 };
    fract(h / 6.0)
}

// OKLab (Björn Ottosson's): { L, a, b, alpha }, L from 0 to 1, a and b
// roughly within +-0.4. Equal steps in it look equal, so mixing, lightening
// and gradients go through it.
fn to_oklab(c: Color) -> float4 {
    let lin = to_linear(c);
    let l = cbrt(0.4122214708 * lin.x + 0.5363325363 * lin.y + 0.0514459929 * lin.z);
    let m = cbrt(0.2119034982 * lin.x + 0.6806995451 * lin.y + 0.1073969566 * lin.z);
    let s = cbrt(0.0883024619 * lin.x + 0.2817188376 * lin.y + 0.6299787005 * lin.z);
    float4 { 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
             1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
             0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s, c.a }
}
fn from_oklab(lab: float4) -> Color {
    let l_ = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z;
    let m_ = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z;
    let s_ = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z;
    let l = l_ * l_ * l_;
    let m = m_ * m_ * m_;
    let s = s_ * s_ * s_;
    from_linear(float4 { 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                         -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                         -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s, lab.w })
}
fn cbrt(x: f32) -> f32 { if x < 0.0 { -pow(-x, (1.0 / 3.0) as f32) } else { pow(x, (1.0 / 3.0) as f32) } }

// OKLCh: OKLab's lightness, chroma (0 to about 0.37) and hue in turns.
fn oklch(l: f64, c: f64, h: f64) -> Color { oklcha(l, c, h, 1.0) }
fn oklcha(l: f64, c: f64, h: f64, a: f64) -> Color {
    let angle = h * TAU;
    from_oklab(float4 { l as f32, (c * cos(angle)) as f32, (c * sin(angle)) as f32, a as f32 })
}
// { L, C, h, alpha }
fn to_oklch(c: Color) -> float4 {
    let lab = to_oklab(c);
    let chroma = sqrt(lab.y * lab.y + lab.z * lab.z);
    let h = if chroma < 0.000001 { 0.0 } else { fract(atan2(lab.z, lab.y) / TAU) };
    float4 { lab.x, chroma, h, lab.w }
}

// --- manipulation ----------------------------------------------------------------

fn with_alpha(c: Color, a: f64) -> Color { Color { c.r, c.g, c.b, a as f32 } }
// Alpha multiplied by k.
fn fade(c: Color, k: f64) -> Color { Color { c.r, c.g, c.b, (c.a * k) as f32 } }

// OKLCh lightness moved by `amount` (lighten(c, 0.1) is a tenth of the way
// from black to white), so equal amounts look like equal steps.
fn lighten(c: Color, amount: f64) -> Color {
    let lch = to_oklch(c);
    oklcha(saturate((lch.x + amount) as f32), lch.y, lch.z, lch.w)
}
fn darken(c: Color, amount: f64) -> Color { lighten(c, -amount) }
// OKLCh chroma multiplied by 1 + k, or 1 - k.
fn saturate(c: Color, k: f64) -> Color {
    let lch = to_oklch(c);
    oklcha(lch.x, max(0.0, lch.y * (1.0 + k)), lch.z, lch.w)
}
fn desaturate(c: Color, k: f64) -> Color { saturate(c, -k) }
// The hue turned by `turns`, in OKLCh, keeping lightness and chroma.
fn rotate_hue(c: Color, turns: f64) -> Color {
    let lch = to_oklch(c);
    oklcha(lch.x, lch.y, lch.z + turns, lch.w)
}
fn invert(c: Color) -> Color { Color { 1.0 - c.r, 1.0 - c.g, 1.0 - c.b, c.a } }
// The gray of the same relative luminance.
fn grayscale(c: Color) -> Color {
    let v = linear_to_srgb(luminance(c));
    Color { v, v, v, c.a }
}

// a and b mixed by t, 0 giving a, in OKLab: midpoints keep their
// lightness and saturation, where sRGB's go dark and dull between
// complementary colors. Mixed premultiplied, as CSS does, so a transparent
// end takes on the other's color rather than darkening it.
fn mix(a: Color, b: Color, t: f64) -> Color {
    from_oklab(mix_premultiplied(to_oklab(a), to_oklab(b), t as f32))
}
// In sRGB's encoding, as most 2D APIs and CSS gradients mix by default.
fn mix_srgb(a: Color, b: Color, t: f64) -> Color {
    from_float4(mix_premultiplied(to_float4(a), to_float4(b), t as f32))
}
// In linear light: physically, as light adds.
fn mix_linear(a: Color, b: Color, t: f64) -> Color {
    from_linear(mix_premultiplied(to_linear(a), to_linear(b), t as f32))
}
// Two { x, y, z, alpha } mixed with x, y and z premultiplied by alpha, and
// divided by it again after.
fn mix_premultiplied(a: float4, b: float4, t: f32) -> float4 {
    let alpha = a.w + (b.w - a.w) * t;
    if alpha <= 0.0 { return float4 { a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t,
                                      a.z + (b.z - a.z) * t, 0.0 }; }
    let pa = float4 { a.x * a.w, a.y * a.w, a.z * a.w, a.w };
    let pb = float4 { b.x * b.w, b.y * b.w, b.z * b.w, b.w };
    let p = lerp(pa, pb, t);
    float4 { p.x / alpha, p.y / alpha, p.z / alpha, alpha }
}

// src drawn over dst with normal alpha blending, in sRGB's encoding as the
// GPU blends by default.
fn blend_over(dst: Color, src: Color) -> Color {
    let a = src.a + dst.a * (1.0 - src.a);
    if a <= 0.0 { return TRANSPARENT; }
    let k = dst.a * (1.0 - src.a);
    Color { (src.r * src.a + dst.r * k) / a, (src.g * src.a + dst.g * k) / a,
            (src.b * src.a + dst.b * k) / a, a }
}

// Relative luminance (WCAG 2), 0 for black to 1 for white; alpha ignored.
fn luminance(c: Color) -> f32 {
    let lin = to_linear(c);
    0.2126 * lin.x + 0.7152 * lin.y + 0.0722 * lin.z
}
// WCAG 2's contrast ratio, from 1 (none) to 21 (black on white).
fn contrast_ratio(a: Color, b: Color) -> f32 {
    let la = luminance(a);
    let lb = luminance(b);
    (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}
// Black or white, whichever is easier to read on `background`.
fn readable_on(background: Color) -> Color {
    if contrast_ratio(BLACK, background) >= contrast_ratio(WHITE, background) { BLACK } else { WHITE }
}

// n colors of even lightness and chroma whose hues are a golden angle apart,
// so any first few of them are far apart: for chart series and debug
// colors. `seed` turns the first hue.
fn palette(n: i64, seed: f64) -> Color[>..] {
    var out: Color[>..] = [];
    for i in n { out.push(oklch(0.72, 0.13, seed + i * 0.381966)); }
    return out;
}
