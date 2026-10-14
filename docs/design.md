# gfx2d: design

A 2D drawing library for [Goose](https://github.com/aardappel/goose), built
on [goose_gfx](https://github.com/aardappel/goose_gfx)'s `gfx` module
(SDL3's GPU API). It covers shapes, paths, colors, paints (gradients and
images), transforms, anti-aliasing and text. goose_gfx's own docs list "a 2D
immediate-mode layer in Goose on top of this one, as Lobster has" as
follow-up work. This package is that layer.

This document is the plan. Its API sketches show the intended shape of the
calls, and names may change during implementation.

**gfx2d uses goose_gfx as it is.** It needs no stencil, no extra blend
factors and no new calls. Everything here uses `gfx`'s current API: its
five blend modes, R8 and RGBA8 render targets, MSAA with resolve, scissor,
storage buffers and instancing. Where an extension to `gfx` would make
something cheaper, the
[Possible gfx extensions](#possible-gfx-extensions) section says so. Those
are later redesigns, not dependencies.

## Goals

* **Simple things are one call.** `gfx2d::circle(400, 300, 100, gfx2d::RED)`
  inside a frame needs no setup, pipeline or font object.
* **Complex things use the same calls.** Every shape also takes a `Paint` in
  place of a color. A paint can be a gradient, an image, a gradient blended
  with an image, or have a blend mode or opacity. Paths take the same paint
  as a circle does.
* **Anti-aliased by default, and resolution-independent.** Primitives are
  drawn from signed distance functions in the fragment shader, so edges stay
  smooth under any affine transform. Paths get an anti-aliased fringe, and a
  canvas can opt into MSAA.
* **Few draw calls.** Shapes, glyphs and images share one pipeline and one
  instance buffer, and a batch ends only when the texture or blend state
  changes.
* **Follows Goose's memory model.** The library uses no heap. Per-frame data
  lives in grow-shrink global arrays that are emptied, not freed, each frame.
  Paths are plain growable arrays that the caller owns.
* **Same structure and conventions as goose_gfx.** That means a package with
  thin `extern fn` wrappers, a small C layer whose `*_api.h` is checked
  against the Goose declarations, headless pixel tests, and a window
  showcase.

Non-goals for v1: complex-script text shaping (HarfBuzz), full SVG, a scene
graph or retained UI (`ui` already exists), and 3D.

## Repository layout

```
goose_gfx2d/
  gfx2d.goose          the entry: frames, canvases, shapes, paints, transforms, images
  color.goose          Color, conversions, manipulation (no GPU, no C)
  transform.goose      Affine, Rect, fit (no GPU, no C)
  path.goose           paths, flattening, stroking, tessellation (no GPU, no C)
  text.goose           fonts, measuring, layout, drawing
  gfx2d.build          sidecar, from phase 4: cmake_target = "goose_gfx2d_package"; main_thread_only
  CMakeLists.txt       from phase 4: builds the text layer with stb_truetype and stb_rect_pack
  src/
    shaders/           shape.glsl/.vert/.frag; later mesh.*, paint.glsl, blit.frag (embed_shader by file)
    text/              text_api.h (GS_GFX2D_TEXT_API), text_font.c, text_atlas.c, text_stb.c
  docs/                design.md (this), gfx2d.md, color.md, path.md, text.md
  examples/            small programs, each a root file
  test/
    run_tests.py       runs pure/ and headless/, compares with expected/
    expected/          <dir>_<name>.out
    api_check.py       text_api.h and text.goose agree, as goose_gfx's does
    headless/          render to a texture, read back, compare (GOOSE_GFX_HEADLESS=1)
    pure/              color, path and tessellation tests that need no GPU
    window/            gfx2d_showcase.goose and run_window_test.py
  third_party/stb      shallow submodule
  third_party/fonts/   the default font: a Latin subset of Inter Regular, with its OFL.txt
  README.md  LICENSE
```

As in goose_gfx, each `.goose` file has the package namespace. All of the
modules use `namespace gfx2d;`, so a user writes `gfx2d::circle`,
`gfx2d::rgb` and `gfx2d::Font` and does not need to know which file defines
them. `gfx2d.goose` imports the other three modules, so a single
`import gfx2d …;` brings in everything.

**Only text needs C.** Shapes, paths, tessellation and color math are
written in Goose, which makes them testable without a GPU and without a C
compiler. Glyph rasterization uses stb_truetype in a static library that
the sidecar names, the same way goose_gfx's layers are built. The library
does not call SDL directly. Everything goes through `gfx`.

## Using it

### Simple

```goose
import gfx;
import gfx2d from "binji/goose_gfx2d@v1";

fn main() {
    gfx::open("hello", 800, 600);
    while gfx::frame() {
        gfx2d::frame(gfx2d::WHITE) {
            gfx2d::circle(400, 300, 100, gfx2d::rgb(0xE04040));
            gfx2d::rect(20, 20, 200, 80, gfx2d::BLUE);
            gfx2d::rounded_rect(20, 120, 200, 80, 12, gfx2d::GREEN);
            gfx2d::line(0, 0, 800, 600, 3, gfx2d::BLACK);
            gfx2d::text(20, 560, "Hello, Goose", 32, gfx2d::BLACK);   // the built-in font
        };
    }
}
```

`gfx2d::frame(clear) { ... }` begins drawing on the screen, runs the block
and flushes. Goose's trailing blocks are compile-time and inline, so this
costs the same as calling `begin` and `end` by hand. Those two functions
also exist.

### Transforms as scopes

```goose
gfx2d::translate(400, 300) {
    for i in 12 {
        gfx2d::rotate(i * TAU / 12) {
            gfx2d::rect(80, -4, 60, 8, gfx2d::hsv(i / 12.0, 0.8, 0.9));
        };
    }
};
```

Each transform call multiplies onto the current matrix, runs the block and
then restores the previous matrix. `gfx2d::push()` and `gfx2d::pop()` are
available for code that doesn't fit into a block.

### Complex: a gradient blended with a texture, stroked and clipped

```goose
let wood = gfx::load_texture("wood.png", gfx::LOAD_MIPS);

let paint = gfx2d::Paint {
    source: gfx2d::linear_gradient(float2 { 0, 0 }, float2 { 300, 200 },
                                   [gfx2d::stop(0.0, gfx2d::rgb(0xFF8800)),
                                    gfx2d::stop(0.6, gfx2d::rgb(0xCC2266)),
                                    gfx2d::stop(1.0, gfx2d::rgba(0x2200AA, 0.8))]),
    image: gfx2d::image_pattern(wood, gfx2d::scale(0.5, 0.5)),   // repeats, in local space
    image_mode: gfx2d::IMAGE_MULTIPLY,      // gradient x texture
    opacity: 0.9,
};

var star: gfx2d::Path = [];
star.star(float2 { 150, 100 }, 5, 90, 40);   // path builders are functions over the array

gfx2d::clip_rounded_rect(0, 0, 300, 200, 24) {
    gfx2d::fill(star, paint);
    gfx2d::stroke(star, gfx2d::Stroke { width: 4, join: gfx2d::JOIN_ROUND,
                                        dash: [8, 4] }, gfx2d::WHITE);
};
```

## Coordinates and frames

* **Coordinates are pixels**, with the origin at the top left and y pointing
  down, like the screen and texture coordinates in `gfx`.
* **Scalar parameters are `f64`.** A Goose float variable is `f64` by
  default and doesn't narrow to `f32` implicitly. Integers, `f32` and
  `f64` all pass to an `f64` parameter, so `circle(x, y, r, c)` works
  whatever types the caller's variables have. The library narrows to `f32`
  internally. Structs that are GPU data, or that are built from
  `float2`/`float4` (`Affine`, `Rect`, corner radii), stay `f32`.
  `rect_of(x, y, w, h)` builds a `Rect` from any numbers.
* **High-density displays.** `gfx` works in pixels and reports the mouse in
  pixels. `gfx2d::set_scale(s)` (or `frame(clear, scale)`) adds a base scale
  so that a program can draw in logical units, and hit testing divides the
  scale back out.
* **Canvases.** `begin(target: gfx::Texture, clear: Color)` draws into any
  color target, and `begin(target)` draws over what is already there.
  `gfx2d` opens and closes its own `gfx` passes, the same way `ui::render`
  does. That lets it switch targets for layers and lets 2D drawing be mixed
  with `ui` and with a program's own 3D passes in either order. A canvas
  can request MSAA (`CanvasDesc { samples: 4 }`), which uses a multisampled
  intermediate texture and a resolve.
* **State** is global, as it is in `gfx`. That includes the current
  transform, clip, default font, blend mode and opacity. All of it is reset
  at `begin`.

## Colors (`color.goose`)

```goose
struct Color { r: f32, g: f32, b: f32, a: f32 }   // sRGB-encoded, straight alpha, 0..1
```

* **Constructors:** `rgb(0xRRGGBB)`, `rgba(0xRRGGBB, a)`, `rgba8(r, g, b, a)`,
  `rgbf(r, g, b)`, `hex("#ff8800cc")`, `gray(v)`, `hsv(h, s, v)`,
  `hsl(h, s, l)`, `oklch(l, c, h)`, `from_linear(float4)`, and
  `from_u32(0xAARRGGBB)`. Named constants include `BLACK`, `WHITE`,
  `TRANSPARENT`, `RED` and the rest of the CSS basic set. A `css` table can
  be added later.
* **Conversions:** `to_linear`, `to_hsv`, `to_hsl`, `to_oklab`, `to_oklch`,
  `to_u32`, `to_float4`, `premultiplied`.
* **Manipulation:** `with_alpha`, `fade(c, k)`, `lighten`, `darken`,
  `saturate`, `desaturate`, `rotate_hue`, `invert`, `grayscale` (luma),
  `mix(a, b, t)` (OKLab by default, `mix_srgb` and `mix_linear` also
  available), `blend_over(dst, src)`, `luminance`, `contrast_ratio` (WCAG)
  and `readable_on(bg)` (black or white). Lightness changes are done in
  OKLCh, so `lighten(c, 0.1)` produces a perceptually even step.
* **Palettes:** `gradient_at(stops, t)` uses the same interpolation as the
  GPU, and `palette(n, seed)` generates distinct hues by golden-angle
  steps in OKLCh.

Color math is all Goose, runs without a GPU, and is tested in `test/pure/`.

**Blending space.** By default the library blends and interpolates
gradients in sRGB, as browsers and most 2D APIs do, so results match what
designers expect. A canvas flag `LINEAR_BLENDING` switches to an sRGB
intermediate target (`RGBA8_SRGB`) for physically correct blending, and
the interpolation space of a gradient is a separate per-gradient field
(`SRGB`, `LINEAR` or `OKLAB`).

## Paint

A paint describes how each covered pixel is colored. The shape decides
which pixels are covered.

```goose
struct Gradient {
    kind: i32,                        // NONE, LINEAR, RADIAL, CONIC
    p0: float2, p1: float2,           // linear: the ends; radial: center, focal point; conic: center
    radius: f32, angle: f32,          // radial; conic
    spread: i32,                      // PAD, REPEAT, REFLECT
    space: i32,                       // INTERPOLATE_SRGB, LINEAR or OKLAB
    stops: Stop[..16],                // inline, up to MAX_STOPS
}

struct Paint {
    color: Color = WHITE,             // the source, or a tint multiplying the gradient
    gradient: Gradient = { .. },      // kind NONE: the color alone
    image: Image = { .. },            // texture, placement, source rect, wrap, filter; none by default
    image_mode: i32 = 0,              // IMAGE_MULTIPLY; also REPLACE, ADD, MASK
    opacity: f32 = 1.0,
    blend: i32 = 0,                   // BLEND_NORMAL, ADD, MULTIPLY, REPLACE
    space: i32 = 0,                   // SPACE_LOCAL: moves with the shape; or SPACE_SCREEN
}
```

This is a struct rather than an enum of sources, so a struct literal can
set just the fields it needs, as in `Paint { gradient: g, opacity: 0.5 }`.
A `Gradient` holds its stops inline (`Stop[..16]`), so a `Paint` is a flat
value with no allocation.

* **The shader evaluates paint in this order:** the source (the color, or
  the gradient tinted by the color), then the image sample combined with
  it by `image_mode`, then `opacity`, then the shape's coverage, and
  finally the result is blended into the target by `blend`.
* **Gradients** have up to 16 stops, a spread mode (`PAD`, `REPEAT`,
  `REFLECT`) and an interpolation space. They're baked on the CPU
  (`paint.goose`, testable without a GPU) into rows of a 256-wide *ramp
  atlas* texture, stored premultiplied so filtering doesn't darken where
  alpha changes. Gradients in the same frame with the same stops and space
  share a row. The paint carries only a row index and the gradient's
  geometry. A radial gradient's focal point is clamped to inside its
  circle.
* **Images** carry a `gfx::Texture`, a placement (an `Affine` from the
  image's pixels into the paint's space), an optional source rectangle in
  pixels (sprite sheets), a wrap mode (`CLAMP`, `REPEAT`, `MIRROR`,
  `DECAL`) and a filter (`LINEAR`, `NEAREST`). A whole texture wraps by its
  sampler. A part of one wraps in the shader, inset half a texel so that
  its neighbors never bleed in, and mip level comes from the unwrapped
  coordinates so the seam doesn't drop to the smallest mip. The default
  mode, `IMAGE_MULTIPLY` with a white color, draws the image as it is.
* **Paint records** are deduplicated against the last one added, so a loop
  drawing many shapes with one paint uploads it once. A shape drawn with a
  `Color` uses paint 0, "the instance's color alone", and needs no record.
* **Blend modes on a paint** are the ones `gfx`'s fixed-function blending
  provides, with coverage and opacity folded into what the shader outputs:
  * `NORMAL` is `gfx::BLEND_PREMULTIPLIED`, with the shader outputting
    premultiplied color times coverage.
  * `ADD` is `gfx::BLEND_ADD`, with coverage in alpha.
  * `MULTIPLY` is `gfx::BLEND_MULTIPLY`, with the shader outputting
    `mix(1, color, alpha * coverage)` so that edges stay anti-aliased.
  * `REPLACE` is `gfx::BLEND_NONE`, with hard edges.

  Each of these is one pipeline variant.
* **Other blend modes need a layer.** `SCREEN`, `ERASE` (destination-out),
  the other Porter-Duff operators, `OVERLAY`, `DARKEN`, `LIGHTEN` and
  `COLOR_DODGE` can't be expressed with those blend factors. They're
  available on layers (see below), where a composite pass samples both the
  layer and a copy of the destination and blends in the shader. This costs
  an extra pass per layer.
* **Shorthands:** every shape takes a `Color` or a `Paint` in the same
  position (the parameter is generic, so there's one function per shape,
  not two). `solid(c)`, `linear(x0, y0, x1, y1, c0, c1)`,
  `radial(cx, cy, r, inner, outer)`, `pattern(texture)`, `paint(gradient)`,
  `paint(image)`, `with_opacity` and `with_blend` build the common paints in
  one call.
* **Batches** are keyed by blend mode and image (texture and sampler). A
  shape without an image fits any batch of its blend mode, and a batch
  without an image takes the first image that comes, so solid shapes
  between sprites from one sheet don't break the batch. The ramp atlas is
  always bound, so gradients never break a batch.

## Shapes (`gfx2d.goose`)

Each primitive has a fill form and a stroke form, and each form accepts
either a `Color` or a `Paint`:

| | fill | stroke |
|---|---|---|
| rectangle | `rect(x, y, w, h, paint)` | `rect_outline(x, y, w, h, width, paint)` |
| rounded rectangle | `rounded_rect(x, y, w, h, r, paint)`, per-corner `float4` radii | `rounded_rect_outline(...)` |
| circle | `circle(cx, cy, r, paint)` | `circle_outline(cx, cy, r, width, paint)` |
| ellipse | `ellipse(cx, cy, rx, ry, paint)` | `ellipse_outline(...)` |
| arc, pie, ring | `pie(c, r, a0, a1, paint)`, `ring(c, r0, r1, paint)` | `arc(c, r, a0, a1, width, cap, paint)` |
| line | | `line(x0, y0, x1, y1, width, paint)`, with caps |
| triangle, quad | `triangle(a, b, c, paint)`, `quad(a, b, c, d, paint)` | via paths |
| polygon | `polygon(points, paint)`, `regular_polygon(c, n, r, paint)` | `polyline(points, width, paint)`, `polygon_outline` |
| image | `image(tex, x, y)`, `image(tex, dst_rect, src_rect)`, `nine_slice(...)` (seamless: inner edges are hard, half-open by pixel center) | |
| shadow | `box_shadow(x, y, w, h, r, blur, color)` | |

Overloads also accept `float2` points and a `Rect { x, y, w, h }` struct, so
the same call can be written with whichever types the caller already has.

**Analytic primitives.** Rectangles, rounded rectangles, circles,
ellipses, arcs, pies, rings, lines and capsules aren't tessellated. Each is
one instance of a quad that bounds the shape, expanded by a pixel for
anti-aliasing. The fragment shader evaluates the shape's signed distance
and turns it into coverage. A stroke of one of these shapes is the same
instance with `|d| - width/2`, so outlines are as cheap as fills and are
centered on the geometry (inner and outer alignment are flags). For an
ellipse, the shader uses the first-order approximation `f / |∇f|`, which
is accurate within the anti-aliasing band. `box_shadow` uses the
closed-form Gaussian-blurred rounded rectangle (as in Evan Wallace's
approximation), so a drop shadow is also a single instance.

## Paths and polygons (`path.goose`)

```goose
enum PathEl {
    Move { p: float2 }, Line { p: float2 }, Quad { c: float2, p: float2 },
    Cubic { c1: float2, c2: float2, p: float2 }, Arc { ... }, Close,
}
// A path is a plain array, so the caller owns it and it is freed at the end of its scope.
alias Path = PathEl[>..<];    // or a one-field struct if Goose has no aliases

fn move_to(p: Path&, x: f32, y: f32)    fn line_to(...)   fn quad_to(...)
fn cubic_to(...)   fn arc_to(...)   fn close(p: Path&)
fn rect / rounded_rect / circle / ellipse / star / polygon(p: Path&, ...)   // shape builders
fn svg_path(p: Path&, d: const u8[:]) -> bool                              // "M10 10 L ... Z"
fn transform(p: Path&, m: Affine)   fn bounds(p) -> Rect   fn contains(p, pt, rule) -> bool
```

* **Fill** (`fill(path, paint, rule)` with `NONZERO` or `EVEN_ODD`):
  curves are flattened adaptively against the current transform, with
  tolerance in pixels, so zooming in adds segments. A convex path, which is
  detected automatically, becomes a fan. Any other path, including
  self-intersecting paths and paths with holes, goes through a
  sweep-line tessellator that handles both fill rules. An anti-aliased
  fringe, a one-pixel band whose alpha ramps along the outline normals, is
  added in the style of nanovg. MSAA canvases leave the fringe out.
* **Stroke** (`stroke(path, Stroke, paint)`): the stroke has a width, a
  join (`MITER` with a limit, `ROUND`, `BEVEL`), a cap (`BUTT`, `ROUND`,
  `SQUARE`), a dash pattern with an offset, and whether it scales with the
  transform (`HAIRLINE`, a 1px stroke at any zoom, is a flag). The stroker
  turns the stroke into a polygon and fills it with `NONZERO`, so
  overlapping parts of a stroke are drawn once and don't double up when the
  stroke is translucent.
* **Retained meshes.** `mesh = gfx2d::tessellate(path, …)` returns a
  `Mesh` (vertices, indices and fringe) that can be drawn every frame
  with `draw(mesh, paint)` and doesn't need tessellating again. Under
  transforms that are only similarity transforms, it stays valid. Large
  static maps and icons use this.
* **Custom geometry.** `draw_triangles(vertices: Vertex[:], indices, paint)`
  takes user meshes (position, uv, color). Per-vertex colors are multiplied
  with the paint, so the same call draws vertex-colored geometry.

Tessellation runs in Goose and writes its output into the frame's
grow-shrink vertex and index arrays without allocating. The tests in
`test/pure/` cover it without a GPU.

## Transforms

```goose
struct Affine { a: f32, b: f32, c: f32, d: f32, tx: f32, ty: f32 }   // x' = a x + c y + tx
```

* **Builders:** `identity`, `translate(x, y)`, `scale(sx, sy)`,
  `scale(s)`, `rotate(angle)`, `rotate_about(angle, cx, cy)`, `skew(ax, ay)`,
  `ortho_fit(src_rect, dst_rect, fit)` (contain, cover or stretch), `mul`,
  `invert`, `apply(m, p)`, `apply_vector` and `decompose`.
* **The current transform** has a scoped form and a function form. The
  scoped form takes a block: `translate(x, y) { }`, `rotate(a) { }`,
  `scale(s) { }`, `transform(m) { }`. The function form operates on the
  stack directly: `push`, `pop`, `set_transform(m)`, `current_transform()`
  and `reset_transform()`. A mismatched `push`/`pop` is a misuse, reported
  the way `gfx` reports misuse: printed, counted, and aborted at `end`.
* **Camera.** `Camera2D { center, zoom, rotation }` produces the view
  matrix, and `screen_to_world(p)` and `world_to_screen(p)` cover mouse
  picking in 2D games.
* **Hit testing.** `hit_rect`, `hit_circle` and `contains(path, …)` take
  points in local space. `to_local(gfx::mouse_pos())` inverts the current
  transform, so testing a transformed shape against the mouse needs one
  call.

Every instance carries its full 2×3 matrix, so a transform doesn't break a
batch. Because the shader computes anti-aliasing from screen-space
derivatives of the distance (`fwidth`), edges stay one pixel wide under
rotation, non-uniform scale and skew.

## Anti-aliasing

| geometry | default | alternatives |
|---|---|---|
| analytic shapes, text | SDF coverage, ~1px band, gamma-aware | `crisp()` mode snaps to pixels and uses a hard step, for pixel art |
| tessellated fills and strokes | 1px fringe | MSAA canvas (`samples: 2/4/8`), which leaves the fringe out |
| images | bilinear plus mips (`LOAD_MIPS`) | `NEAREST` sampler for pixel art |

The global setting `set_antialias(false)` is the "pixel art" switch. It
turns off the SDF band and the fringe, uses nearest sampling, and rounds
instance positions to whole pixels. Thin strokes (width under 1px) are
drawn at 1px width with alpha scaled by the width, which avoids the
flicker that sub-pixel strokes cause.

## Text (`text.goose`, `src/text/`)

* **Fonts:** `load_font(path)` and `font_from_memory(bytes)` load any
  TrueType or OpenType font, and `set_default_font(font)` makes one the
  default for calls that don't name a font. A font is a handle, and size is
  a parameter at draw time, not a property of the font.
* **The built-in font** is [Inter](https://github.com/rsms/inter) Regular
  (SIL Open Font License 1.1), which `default_font()` returns. It is
  vendored in `third_party/fonts/` together with its `OFL.txt`, subset with
  fonttools' `pyftsubset` to these ranges:
  * Basic Latin, Latin-1 Supplement and Latin Extended-A,
  * General Punctuation,
  * the common currency signs and arrows,
  * `kern`/`GPOS` kerning.

  The subset is about 100 KB. `text.goose` includes it with Goose's
  `embed_file`, which puts it in the program's static data, so the default
  font needs no file at run time and no C build step of its own. A script
  under `third_party/fonts/` records the exact command and the upstream
  version, so the subset can be regenerated. The subset keeps the license
  notice, and if the font declares a Reserved Font Name, the subset is
  renamed as the OFL requires. Text in other scripts needs a font loaded
  for it, added with `add_fallback`.
* **Rendering uses SDF glyphs.** The C layer rasterizes each glyph once with
  `stbtt_GetGlyphSDF` at a base size (around 48px, with an 8px spread) into
  an R8 atlas page, and stb_rect_pack packs new glyphs as they are first
  used. Each glyph is drawn as an instance of the shared shape pipeline, so
  text can be scaled and rotated, uses the same paint (gradient text,
  textured text), and offers `outline` and `glow` from the same distance
  field at no extra cost. Very small text (under about 12px) benefits from
  hinted bitmaps, so a `FontDesc { mode: BITMAP }` rasterizes coverage at
  the exact pixel size instead.
* **Drawing and measuring:** `text(x, y, str, size, paint)`,
  `text(pos, str, TextStyle)`, `measure(str, style) -> float2`,
  `line_height`, `ascent`/`descent`, `glyph_positions(str, style, out)` (for
  carets and selection), and `char_index_at(str, style, x)` for hit testing
  inside text.
* **Layout:** `TextStyle { font, size, align (LEFT/CENTER/RIGHT), baseline
  (TOP/MIDDLE/ALPHABETIC/BOTTOM), line_spacing, letter_spacing, wrap_width,
  overflow (CLIP/ELLIPSIS) }`. Text is decoded as UTF-8 and kerned from the
  font's `kern`/`GPOS` tables through stb_truetype, and wrapping follows
  spaces and explicit newlines.
* **Fallback fonts:** `add_fallback(font, other)` handles glyphs a font
  doesn't have, such as symbols and CJK. Each glyph comes from a single
  font, and nothing is shaped.

The C API (`src/text/text_api.h`, `GS_GFX2D_TEXT_API`) is small: load or
unload a font, get metrics, get a glyph's metrics and kerning, rasterize a
glyph (SDF or coverage) into a caller-supplied byte slice, and pack
rectangles. Atlas pages are `gfx` textures that the Goose side creates and
updates. The C side never sees `gfx` or SDL. `test/api_check.py` checks
the header against `text.goose`, as goose_gfx's does.

`ui` already has Nuklear's font atlas. `gfx2d` doesn't reuse it, because
those glyphs are fixed-size bitmaps, and scalable, paintable text is one of
this library's main features. The two can be used in the same frame.

## Clipping and layers

* **Rectangle clips.** `clip_rect(x, y, w, h) { }` uses `gfx::scissor`
  when the current transform is axis-aligned, intersects with the clip
  already in effect, and costs nothing per instance.
* **Shape clips.** `clip_rounded_rect`, `clip_circle` and `clip_path` handle
  clips under rotation. Analytic clips (a rounded rectangle or circle)
  travel with each instance as a clip SDF that is evaluated in the
  fragment shader. That covers the common cases, such as rounded panels and
  circular avatars, without a separate pass. An arbitrary `clip_path`
  renders the path's anti-aliased coverage into an R8 mask texture the
  size of the clip's bounds. Draws inside the clip sample that texture and
  multiply by it. Nested path clips multiply their masks together.
* **Layers** (`layer(LayerDesc { opacity, blend, filter }) { … }`) draw into
  an offscreen texture of the region they cover and then composite it. This
  is what group opacity (a translucent group whose overlapping parts don't
  double up), the non-separable blend modes and filters (`blur(radius)`,
  `drop_shadow`, `color_matrix`) are built on. Layer textures are pooled by
  size for the duration of a frame.

## Rendering architecture

```
draw calls ─► instance records (Goose, global grow-shrink arrays)
              mesh vertices / indices (tessellated paths)
              paint records, ramp atlas rows, glyph atlas uploads
end / flush ─► one storage-buffer upload per kind
              ─► for each batch run: bind textures, draw_instanced / draw_indexed
```

* **Two pipelines.** `shape` draws instanced quads with vertex pulling from
  a storage buffer of `ShapeInstance` records. It handles every analytic
  primitive, glyphs and images. `mesh` draws indexed triangles for
  tessellated paths and user geometry. Both index the same `PaintGPU`
  storage buffer and share one fragment-shader paint function, kept in a
  `paint.glsl` that both include.
* **Instance record** (sketch, about 96 bytes, packed to std430):
  the matrix rows, the shape kind and flags, a rectangle or half-extents,
  four corner radii or arc angles, stroke width, a clip SDF index, and a
  paint index. Laying out the Goose struct exactly as std430 does is
  checked by a test, the way `push_uniforms` checks size.
* **Batches** break only on a change of texture binding, blend state, scissor
  or canvas. Glyph atlas pages and the ramp atlas are bound at all times,
  in slots of their own, so text and gradients don't break batches. User
  textures do. Draw order is the order of calls, and the library never
  reorders draws, so painter's-algorithm semantics are kept.
* **Memory.** Per-frame arrays are globals declared `T[>..<]`, each on its
  own data stack, and `resize(0)` empties them at `begin`. GPU buffers grow
  geometrically and are recreated when a frame needs more. Rewriting an
  entire buffer lets SDL cycle it instead of stalling, as noted in
  goose_gfx's docs.
* **Device lifetime.** As `ui` does with `renderer.opened != gfx::open_count()`,
  the library recreates its pipelines, atlases and buffers lazily after
  `gfx` is closed and opened again.
* **Errors** follow `gfx`'s two kinds. A failure outside the program's
  control (a missing font file) returns a zero handle and sets
  `gfx2d::error()`. Misuse (unbalanced scopes, drawing outside a frame)
  is counted and aborted at `end`.

## Testing

Testing follows goose_gfx:

* **`test/pure/`**: color conversions (round trips, known values), OKLab
  mixing, path flattening tolerance, tessellation (triangle-area sums equal
  path area under both fill rules, and fixtures for holes,
  self-intersection and degenerate input), stroker joins and caps, and
  affine math. These need no GPU or C.
* **`test/headless/`**: a program renders into a texture under
  `GOOSE_GFX_HEADLESS=1` and reads it back. Pixel-aligned rectangles and
  solid fills must match exactly on every backend. Anti-aliased edges are
  checked against analytic coverage within a tolerance. Gradient endpoint
  and midpoint colors, blend modes, clip containment and glyph presence
  (ink inside the measured box) are also tested. A machine without a GPU
  reports these tests as skipped.
* **`test/window/`**: a showcase scene with every feature, which saves
  screenshots, and `run_window_test.py`, which compares them across
  backends and between JIT and AOT runs.
* **`test/api_check.py`** checks the text layer's header against
  `text.goose`.

## Possible gfx extensions

v1 doesn't depend on any of these. goose_gfx lists some of them as
follow-up work. If `gfx` gains them, the parts below can be redesigned to
use them, and the public API stays the same.

| extension | what it would make cheaper | what v1 does instead |
|---|---|---|
| stencil attachment and ops | `clip_path` without a mask texture; stencil-then-cover fills | R8 mask textures; CPU tessellation |
| more blend factors, blend constants | `SCREEN`, `ERASE` and Porter-Duff operators directly on a paint, without a layer | composite pass from a layer |
| dual-source blending | subpixel (LCD) text | grayscale anti-aliased text |

## Suggested features beyond the brief

Ordered by value to typical users. The first group belongs in v1.

**v1, because they're expected**

1. **Images and sprites**: source rectangles, flipping, tinting,
   `nine_slice` for UI panels, and a `SpriteAtlas` that packs many small
   images into one texture so that they share a batch.
2. **Box shadows and blur**: the analytic rounded-rectangle shadow, plus
   layer blur for anything else.
3. **Dashed lines and polylines** with joins, and **Bézier curves** via
   paths.
4. **Clipping**: rectangle, rounded rectangle and path clips.
5. **Hit testing and a 2D camera**: `screen_to_world`, `contains`,
   `to_local`.
6. **Pixel-art mode**: no anti-aliasing, nearest sampling, integer
   snapping, and an integer-scaled virtual resolution
   (`virtual_canvas(320, 180)`, letterboxed to fit the window).

**Next, common in libraries like this**

7. **Render-to-texture and layers** with group opacity and blend modes.
8. **SVG path data** (`svg_path(p, "M…")`) and a minimal SVG loader for
   icons (paths, fills, strokes, gradients).
9. **Text extras**: rich text runs (several styles on one line), carets and
   selection helpers, and outline and shadow.
10. **Instanced bulk drawing**: `circles(centers, radii, colors)` for
    particles and data visualization, filling instance records directly
    from slices.
11. **Debug overlay and statistics**: draw calls, instances, batch breaks
    and their causes, and atlas usage. `gfx2d::stats()` returns the
    numbers.
12. **Easing and tween helpers** next to color `mix`, which make simple
    animation easy (small, pure Goose).

**Later**

13. **Filters**: color matrix (sepia, grayscale, hue rotation), bloom, and
    a custom fragment shader on a layer (the user supplies an
    `embed_shader` with a fixed interface).
14. **Path boolean operations** (union, intersect, difference) and
    offsetting.
15. **Mesh gradients and gradients along a path.**
16. **Saving vector output to SVG or PDF** from the same draw calls, which
    becomes possible if draw calls are kept in an optional display list.
17. **Complex-script text shaping** with HarfBuzz behind the same API.

## Phases

1. **Core** (done): the package skeleton, the `shape` pipeline, solid-color
   analytic shapes (rect, rounded rect, circle, ellipse, ring, pie, arc,
   line; fills and outlines), transforms, the color module, the test runner,
   pure and headless tests, and `examples/shapes.goose`. The sidecar and
   CMake wait for phase 4, the first C.
2. **Paint** (done): gradients with the ramp atlas, image patterns and
   image modes, the four fixed-function blend modes, images and sprites,
   nine-slice, and `examples/paint.goose`.
3. **Paths**: flattening, convex and general tessellation, the fringe,
   stroker with joins, caps and dashes, retained meshes, polygons.
4. **Text**: the stb_truetype layer, the vendored Inter subset, SDF atlas,
   measure and layout, and outline and glow.
5. **Clip and layers**: rectangle and analytic clips, R8 mask clips,
   layers with group opacity and the shader-composited blend modes, blur
   and shadows, MSAA canvases.
6. **Polish**: camera and hit testing, pixel-art mode, statistics, the
   showcase, and docs (`docs/gfx2d.md` written as goose_gfx's `gfx.md` is).

## Decisions

* **The name is `gfx2d`**, as both the package and the namespace. Import
  aliases may come to Goose later, and the name doesn't depend on them.
* **gfx2d builds on goose_gfx as it is.** Possible extensions are listed
  above for a later redesign.
* **Blending is in sRGB by default**, which matches CSS and most 2D APIs.
  Linear blending is an opt-in canvas flag that uses `gfx`'s existing
  `RGBA8_SRGB` format.
* **The default font is a vendored Latin subset of Inter Regular** (OFL
  1.1). Any TrueType or OpenType font can be loaded and made the default.

## Open questions

* **Global state or explicit `Canvas` values.** `gfx` is global and
  main-thread-only, so this design is too. An explicit canvas parameter
  would allow recording draw lists to submit later.
