# gfx2d: design

A 2D drawing library for [Goose](https://github.com/aardappel/goose), built
on [goose_gfx](https://github.com/aardappel/goose_gfx)'s `gfx` module
(SDL3's GPU API). It covers shapes, paths, colors, paints (gradients and
images), transforms, anti-aliasing and text. goose_gfx's own docs list "a 2D
immediate-mode layer in Goose on top of this one, as Lobster has" as
follow-up work. This package is that layer.

This document is the plan the library was built from, with the reasoning
behind its decisions. Its API sketches show the intended shape of the
calls, and some names changed during implementation. All six phases are
done; [gfx2d.md](gfx2d.md) is the reference for what was built.

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
  gfx2d.build          sidecar: cmake_target = "goose_gfx2d_package"; main_thread_only
  CMakeLists.txt       builds the text layer with stb_truetype
  src/
    shaders/           shape.glsl/.vert/.frag; later mesh.*, paint.glsl, blit.frag (embed_shader by file)
    text/              text_api.h (GS_GFX2D_TEXT_API), text_font.c
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
  third_party/fonts/   the default font: a Latin subset of Inter Regular, its OFL.txt, and
                       make_subset.sh and unwrap_extensions.py, which made it
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
  pixels. A base scale (`gfx2d::set_scale(s)`, or `frame(clear, scale)`), so
  that a program can draw in logical units with hit testing dividing the
  scale back out, is not built yet ([work.md](work.md), item 18).
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
designers expect. The interpolation space of a gradient is a per-gradient
field (`INTERPOLATE_SRGB`, `LINEAR` or `OKLAB`). A canvas flag for
physically correct blending, through an sRGB intermediate target
(`gfx::RGBA8_SRGB`), was planned and is not built: blending is in sRGB.

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
  alpha changes. Gradients with the same stops and space share a row, and
  the rows are kept between frames: a gradient drawn every frame is baked
  and uploaded once. The atlas holds 4,096 rows; full, it draws further
  gradients as their middle color for the rest of that frame (the frame's
  paints name its rows) and starts over at the next. The paint carries
  only a row index and the gradient's geometry. A radial gradient's focal
  point is clamped to inside its circle.
* **Images** carry a `gfx::Texture`, a placement (an `Affine` from the
  image's pixels into the paint's space), an optional source rectangle in
  pixels (sprite sheets), a wrap mode (`CLAMP`, `REPEAT`, `MIRROR`,
  `DECAL`) and a filter (`LINEAR`, `NEAREST`). A whole texture wraps by its
  sampler. A part of one wraps in the shader, inset half a texel so that
  its neighbors never bleed in, and mip level comes from the unwrapped
  coordinates so the seam doesn't drop to the smallest mip. The default
  mode, `IMAGE_MULTIPLY` with a white color, draws the image as it is.
* **Paint records** are shared through a hash table of the frame's, so a
  loop drawing many shapes with a few paints uploads each once, wherever
  they come. A shape drawn with a `Color`, or with a paint that is a color
  at an opacity, uses paint 0, "the instance's color alone" (the opacity
  folded into the color), and needs no record.
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
    Cubic { c1: float2, c2: float2, p: float2 }, Close,
}
// The caller owns a path, and it is freed at the end of its scope.
struct Path { els: PathEl[>..] = [] }

fn move_to(p: Path&, x: f64, y: f64)   line_to   quad_to   cubic_to   close   clear
fn arc(p: Path&, cx, cy, r[, ry], a0, a1)          // as cubics of at most a quarter turn
fn rect / rounded_rect / circle / ellipse / polygon / regular_polygon / star(p: Path&, ...)
fn transform(p: Path&, m: Affine)   bounds(p) -> Rect   contains(p, pt, rule) -> bool
```

From outside the namespace these are written `gfx2d::move_to(p, x, y)`,
not `p.move_to(x, y)`. Goose looks up method-call syntax in the caller's
namespace, not the argument type's (an "associated-namespace lookup" that
Goose's namespaces design leaves for later).

* **Flattening.** Bézier control points are transformed by the current
  transform first (an affine transform maps a Bézier curve to the Bézier
  curve of the mapped control points), and the curve is flattened in
  pixels by Wang's formula to a 0.1 px tolerance, so zooming in adds
  segments.
* **Fill** (`fill(path, paint, rule)` with `NONZERO` or `EVEN_ODD`). A
  single convex contour, detected automatically, becomes a fan, with its
  outline moved in by half a pixel and a one-pixel fringe ramping alpha
  from 1 to 0 across the true edge. That gives exact coverage, as nanovg
  does. Any other fill (holes, self-intersection, several contours) is cut
  into horizontal bands at every vertex's y and every crossing. Within a
  band, sorted by x at its middle, the fill rule picks the spans. A span
  bounded by the same two edges as one in the band above continues that
  span's trapezoid, so a trapezoid is emitted only when its edges change,
  and the output is close to linear in the outline's size. (Without that,
  a 5,000-point outline made 500,000 triangles; with it, 20,000.) The
  sweep has a work budget: a path that crosses itself millions of times
  is drawn in part, with a warning, instead of taking minutes or running
  out of memory. The trapezoids tile the fill exactly, and an
  outward fringe half a pixel wide (alpha ½ to 0) is added along each
  contour on the side away from the fill. The side is found by testing
  the winding number just beside one edge. So these fills come out about
  ⅛ px per unit of outline larger than exact, with slightly crisper edges
  than the analytic shapes.
* **Stroke** (`stroke(path, width, paint)` or
  `stroke(path, Stroke { width, join, cap, miter_limit, dash, dash_offset, pixels }, paint)`):
  * An opaque stroke (a color or a paint with no transparency, blended
    normally) is emitted straight from the flattened line: a quad a
    segment, a fan at each join's outer corner from the inner corner,
    caps, and a fringe along the edges, exact along a straight one. Where
    it overlaps itself (crossings, the inner side of a sharp join between
    short segments) it is drawn twice, which an opaque paint does not show.
    Each point's edge vertices are made once and shared by the segments
    and the join at it, so a chart's lines take a third fewer triangles
    and well under half the bytes of the sweep's, in half the time
    (`bench`'s `chart` against `chart_translucent`).
  * For a translucent stroke, the stroker makes one outline per open
    subpath and two per closed one, and fills them by `NONZERO`. A stroke
    that crosses itself is drawn once where it overlaps, so translucent
    strokes don't darken there.
  * A stroke longer than 16 segments is outlined in pieces of about 16,
    each tessellated alone. One outline that long makes the band sweep's
    work grow with the square of its length: a 1,000-point chart line
    took seconds. Pieces meet across the middle of a segment, the longest
    in the second half of the piece, where both have the same butt end,
    so they leave no gap, and the edges there get no fringe. They also
    don't overlap unless even that segment is shorter than about the
    stroke's width, so that a join beside the cut reaches across it. Only
    a translucent stroke shows that, as small darker spots.
  * Joins can be `MITER` (falling back to bevel past the limit), `ROUND`
    or `BEVEL`. On the inner side of a join, the outline uses the point
    where the two sides meet, and pivots through the vertex only when that
    point would lie past either segment's end.
  * Dashes cut the flattened line before stroking.
  * A stroke is made in the space the path is drawn in, so it stretches
    with the transform like a pen. With `pixels: true` its width is in
    pixels instead.
  * Strokes thinner than a pixel are drawn one pixel wide, with alpha
    scaled by the width.
* **Polygons:** `polygon(points, paint)`, `triangle`, `quad`,
  `polyline(points, width, paint, cap, join)`, `polygon_outline`,
  `regular_polygon`, `star`.
* **Known limitation.** Every edge of the outline gets a fringe, including
  edges inside the fill: the inner parts of a path or stroke where it
  crosses itself. With an opaque paint that's invisible. With a
  translucent one, faint lines show where a stroke crosses itself. The fix
  is to put the fringe only on the stretches of edges that are fill
  boundaries, which the band sweep already finds (the edges at span ends).
* **SVG path data** (`svg_path`) and `warp` (every point of a path through
  a function) came with the Goose logo example. Elliptical arcs aren't
  parsed.
* **Retained meshes:** `tessellate(path, rule, scale)` and
  `tessellate_stroke(path, stroke, scale)` make a `Mesh` once, in the
  path's own space with the curves flattened and the fringe sized for
  `scale` pixels a unit, and `draw(mesh, paint)` draws it every frame
  under the current transform. Its vertices are still uploaded each frame;
  keeping them on the GPU is later work.
* **Later:** user triangle meshes with per-vertex colors and uvs.

Tessellation runs in Goose, into the frame's grow-shrink arrays, and is
tested without a GPU in `test/pure/path.goose`. Those tests check areas by
summing triangles, which is exact whatever way the fill was cut, under
both rules, for holes, pentagrams, bow ties and every join and cap. They
also check that the fringe lies outside the fill, since an area test
can't tell which way a fringe faces.

## Transforms

```goose
struct Affine { a: f32, b: f32, c: f32, d: f32, tx: f32, ty: f32 }   // x' = a x + c y + tx
```

* **Builders** are nouns, since the verbs change the current transform:
  `IDENTITY`, `translation(x, y)`, `scaling(sx, sy)`, `scaling(s)`,
  `rotation(angle)`, `rotation_about(angle, cx, cy)`, `skewing(ax, ay)`,
  `fit(src_rect, dst_rect, FIT_*)` (contain, cover or stretch), `mul`,
  `invert`, `apply(m, p)`, `apply_vector`, `determinant`, `axis_scales`
  and `angle_of`.
* **The current transform** has a scoped form and a function form. The
  scoped form takes a block: `translate(x, y) { }`, `rotate(a) { }`,
  `scale(s) { }`, `transform(m) { }`. The function form operates on the
  stack directly: `push`, `pop`, `set_transform(m)`, `current_transform()`
  and `reset_transform()`. A mismatched `push`/`pop` is a misuse, reported
  the way `gfx` reports misuse: printed, counted, and aborted at `end`.
* **Camera.** `Camera2D { center, zoom, rotation }` produces the view
  matrix, and `screen_to_world(p)` and `world_to_screen(p)` cover mouse
  picking in 2D games.
* **Hit testing.** `in_rect`, `in_rounded_rect`, `in_circle`, `in_ellipse`
  and `contains(path, …)` take points in local space. `to_local(p)` inverts
  the current transform, and `mouse_local()` does it for the mouse, so
  testing a transformed shape against the mouse needs one call.

Every instance carries its full 2×3 matrix, so a transform doesn't break a
batch. The vertex shader works out how far in local units one pixel is
from that matrix (an affine map, so it is the same over the quad; taking
derivatives in the fragment shader found the same), and the fragment
shader antialiases over that, so edges stay one pixel wide under rotation,
non-uniform scale and skew. An instance with no paint record and no clip,
which most are, skips the paint and clip code altogether.

## Anti-aliasing

| geometry | default | alternatives |
|---|---|---|
| analytic shapes, text | SDF coverage, a ~1px linear band | `set_antialias(false)`, or `antialias(false) { }`: a pixel is covered by its center, for pixel art |
| tessellated fills and strokes | 1px fringe | a multisampled frame (`samples: 2/4/8`), which leaves the fringe out |
| images | bilinear plus mips (`LOAD_MIPS`) | `FILTER_NEAREST`, the default with antialiasing off |

The global setting `set_antialias(false)` is the "pixel art" switch. It
turns off the SDF band and the fringe and samples images nearest; a
`pixel_canvas` draws at a small size and scales up by a whole number. Thin
strokes (width under 1px) are drawn at 1px width with alpha scaled by the
width, which avoids the flicker that sub-pixel strokes cause.

## Text (`text.goose`, `src/text/`)

* **Fonts:**
  * `load_font(path)` and `font_from_memory(bytes)` load any TrueType or
    OpenType font, or one font of a collection.
  * `set_default_font(font)` makes a font the default for calls that
    don't name one.
  * `add_fallback(font, other)` chains fonts for characters a font lacks.
  * `release(font)` frees a font.

  A font is a handle, and size is a parameter at draw time, not a property
  of the font.
* **The built-in font** is [Inter](https://github.com/rsms/inter) 4.1
  Regular (SIL Open Font License 1.1), which `default_font()` returns. It
  is subset to Latin, Latin-1, Latin Extended-A, punctuation, currency
  signs and arrows, keeping kerning and dropping hinting. The result is
  48 KB, in `third_party/fonts/` with `OFL.txt`. `make_subset.sh` records
  the upstream release, its hashes and the exact `pyftsubset` command. It
  then unwraps the GPOS Extension lookups, since stb_truetype reads
  kerning only from plain Pair Adjustment lookups, and most of Inter's is
  in extensions. `text.goose` includes the font with `embed_file`, so the
  default font needs no file at run time. The license names no Reserved
  Font Name, so the subset keeps Inter's name.
* **Rendering uses SDF glyphs.**
  * The C layer rasterizes each glyph once, at a 48 px em with a 6 px
    spread. It renders the glyph's coverage with stb_truetype's scanline
    rasterizer, then runs a linear-time Euclidean distance transform
    (Felzenszwalb), placing the edge within partly covered pixels by
    their coverage, as Mapbox's TinySDF does. That takes about 0.15 ms a
    glyph, where `stbtt_GetGlyphSDF`, which measures every pixel against
    every edge, took about 2 ms, with the same geometry and values.
  * `text.goose` packs the glyphs into a shelf-packed R8 atlas, 1024 px
    wide and growing taller to 4096 px. If it fills, text needing new
    glyphs is missing for the rest of that frame, and the atlas starts
    over at the next (the frame's instances name places in the atlas as
    it is). Only changed rows are uploaded.
  * A glyph is an instance of the shape pipeline (`KIND_GLYPH`). Its
    distance comes from the atlas instead of a formula and becomes
    coverage the same way, so text scales, rotates and takes any paint
    (gradient text, textured text, blend modes).
  * `outline` draws the glyph's distance field as a stroke. Its width is
    limited by the spread: about 6 px × size / 48.
  * Under a translation-only transform, the baseline is snapped to whole
    pixels.
  * Text under about 12 px is readable but soft. A hinted-bitmap mode for
    small sizes is follow-up work.
* **Drawing and measuring:** `text(x, y, str, size, paint)`,
  `text(x, y, str, TextStyle, paint)`, `measure_text(str, size | style) -> float2`,
  `font_ascent`, `font_descent` and `font_line_height`.
* **Layout:** `TextStyle { font, size, align (LEFT/CENTER/RIGHT), baseline
  (TOP/MIDDLE/ALPHABETIC/BOTTOM), line_spacing, letter_spacing, wrap_width,
  outline }`. Text is decoded as UTF-8 (an invalid byte is U+FFFD on its
  own) and kerned through stb_truetype. Lines break at newlines and, with
  a wrap width, at the last space that fits. A word wider than the wrap
  width gets a line of its own. What the font answers is kept on the
  Goose side, so a line is laid out without calling into C: the glyph a
  character resolves to (through the fallbacks) and the kerning of a pair
  in two hash tables, and a glyph's advance in its atlas slot, which is
  made the first time the glyph is measured and gets its bitmap the first
  time it is drawn. `text` and `measure_text` lay the text out once, into
  arrays of placed glyphs and lines, and draw or measure from those.
* **No shaping.** Each character is one glyph, so scripts that need
  shaping (Arabic, Devanagari) don't come out right. HarfBuzz behind the
  same API is listed as later work.

The C API (`src/text/text_api.h`, `GS_GFX2D_TEXT_API`) has nine functions:
load, release and validity, the font count of a file, font metrics, glyph
lookup, glyph metrics, kerning, and rasterizing a glyph's SDF into a
caller's buffer. The C side never sees `gfx` or SDL. stb_truetype is
compiled into it `static`, so a program that also links Nuklear's copy (in
`ui`) has no clash. `test/api_check.py` checks the header against
`text.goose`: the function names, the parameter counts, and the fields of
the structs that cross. The built-in font is also why the package has a
sidecar (`gfx2d.build`, CMake target `goose_gfx2d_package`), which the
Goose compiler builds the first time a program uses the package.

`ui` already has Nuklear's font atlas. `gfx2d` doesn't reuse it, because
those glyphs are fixed-size bitmaps, and scalable, paintable text is one of
this library's main features. The two can be used in the same frame.

## Clipping and layers (`layer.goose`)

Both are scoped blocks: the clip or layer applies to what the block draws
and ends with it.

* **Analytic clips:** `clip_rect`, `clip_rounded_rect` (one radius or four),
  `clip_circle` and `clip_ellipse`.
  * Each is a 64-byte clip record (the pixel-to-clip transform, its kind,
    half extents and radii) in a per-frame storage buffer, with its parent
    clip.
  * Every shape instance carries the index of the clip it was drawn under.
    Every mesh batch carries one in a uniform, which keeps mesh vertices at
    24 bytes.
  * The fragment shaders multiply coverage by the clip chain's coverage
    (`clip_coverage.glsl`). That's the clip's distance function,
    antialiased with the pixel size taken from the clip transform's
    determinant, so it's correct under rotation and skew.
  * Nesting is the chain. An analytic clip costs no pass and no batch
    break; `clips` draws 10,000 shapes under 100 rounded clips in one
    draw call.
  * Clips are exact on pixel boundaries, and within about 1/8 px per
    pixel of edge at fractional ones.
* **Path clips:** `clip_path(path, rule) { }`.
  * The path is filled (with its fringe) into an R8 mask texture of the
    target's size, from the pool, in a pass of its own.
  * It's filled under the clips already in effect, so the mask contains
    them and the mask clip's parent is none.
  * Draws inside sample the mask at their pixel, and a mask breaks batches
    (it's a texture binding). Each path clip costs a mask pass, plus a
    pass to resume the target.
* **Layers:** `layer(LayerDesc { opacity, blend, blur, shadow, shadow_offset, shadow_blur }) { }`,
  or `layer(opacity) { }`.
  * The block is drawn into a pooled RGBA8 texture of the target's size,
    cleared, in its own pass, with the clip reset. The clip in effect at
    the layer applies to its compositing instead, so blurs and shadows are
    clipped too.
  * The target's pass then resumes, and a full-target triangle composites
    the layer (`composite.frag`).
  * `NORMAL`, `ADD`, `MULTIPLY` and `REPLACE` composite with gfx's
    fixed-function blending, the same as paints.
  * `SCREEN`, `OVERLAY`, `DARKEN`, `LIGHTEN`, `COLOR_DODGE`, `COLOR_BURN`,
    `HARD_LIGHT`, `SOFT_LIGHT`, `DIFFERENCE` and `EXCLUSION` (the W3C
    separable modes), and `ERASE` (destination-out) and `KEEP`
    (destination-in), need what's under the layer. The target is copied
    into a backdrop texture by a copy pass, and the shader blends the two
    and writes the result.
  * `blur` (a gaussian's sigma) blurs the layer with two separable passes;
    from sigma 5 at half resolution and from 10 at a quarter, after a box
    downsample pass, with the sigma scaled and the box's and the upsample's
    own blur taken off it (their variances: (f² − 1) / 12 and f² / 6 for
    a factor f), so the result keeps the gaussian's width within a few
    levels of 255.
  * A drop shadow composites the layer's alpha, blurred by `shadow_blur`,
    in `shadow`'s color at `shadow_offset`, before the layer itself.
  * A paint whose blend is one of the layer-only modes is a misuse.
* **`box_shadow(x, y, w, h, r, blur, paint, spread)`** is a shape: one
  instance (`KIND_SHADOW`). Its coverage is a rounded box convolved with a
  gaussian, worked out in closed form across one axis and in four steps
  along the other (Evan Wallace's method). `blur` is CSS's box-shadow
  blur, twice the sigma.
* **Multisampled frames:** `begin(target, clear, samples)` and
  `frame(clear, samples) { }`.
  * The frame draws into a pooled multisampled texture that resolves into
    the target at every pass end. gfx stores multisampled contents across
    passes, so layers and path clips can split the frame.
  * Paths drawn into it get no fringe, since the samples antialias them.
    Analytic shapes keep their own antialiasing.
  * Drawing over a target without clearing copies it in first.
* **Passes.** A frame is a list of passes, and everything is still
  uploaded once.
  * A draw pass draws a run of batches into a target, multisampled and
    resolved or not. `flush_batches` keeps what the pass has bound and
    binds, for each batch, only what changes: gfx hands every call on, a
    pipeline bound again makes SDL rebuild its descriptor sets at the next
    draw, and a uniform block pushed again is copied again. What a draw
    call then costs is the driver's descriptor update when its texture
    differs from the last one's (a third of the `sprites_alternating`
    benchmark's process time, in the Intel Vulkan driver), which only
    fewer texture changes, an atlas, can cut.
  * A blur pass draws a texture blurred one way, or copied, into another.
  * A layer adds 2 passes, a backdrop blend mode 2 more, each blur 2 (and
    one downsample at a lower resolution, shared by a blur and a shadow at
    the same one), and a path clip 2. A draw pass with nothing to draw
    that clears nothing is skipped.
  * A layer's passes touch only the pixels its block drew (the bounds of
    its instances' quads and its meshes' vertices, and of the layers
    inside it), grown by the reach of its blur and its shadow: the clear
    is a scissored composite of nothing (or the pass's own clear, when the
    bounds cover most of the target), the blur passes, the backdrop copy
    and the composites are scissored, and a layer whose block drew nothing
    is dropped, passes and all. `BLEND_KEEP` is the exception: it clears
    the target wherever the layer is not, so it composites all of it.
  * Pooled textures come back every frame and are made again only when
    the target's size changes or gfx is reopened. One left unused for
    eight frames is released, or for two if it is not the target's size,
    so a window resized does not keep every size it passed through.
* **Later:** a color-matrix filter, glow, scissor for axis-aligned
  rectangle clips (cheaper than the shader, but without antialiasing at
  fractional edges), and layers the size of their contents rather than of
  the target.

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

Ordered by value to typical users. The first group belongs in v1, and
all of it is built but the sprite atlas.

**v1, because they're expected**

1. **Images and sprites**: source rectangles, flipping, tinting,
   `nine_slice` for UI panels, and a `SpriteAtlas` that packs many small
   images into one texture so that they share a batch (the atlas is not
   built; a texture array for sprites is in gfx2d.md's follow-ups).
2. **Box shadows and blur**: the analytic rounded-rectangle shadow, plus
   layer blur for anything else.
3. **Dashed lines and polylines** with joins, and **Bézier curves** via
   paths.
4. **Clipping**: rectangle, rounded rectangle and path clips.
5. **Hit testing and a 2D camera**: `screen_to_world`, `contains`,
   `to_local`.
6. **Pixel-art mode**: no anti-aliasing, nearest sampling, integer
   snapping, and an integer-scaled virtual resolution
   (`virtual_canvas(320, 180)`, letterboxed to fit the window: built as
   `pixel_canvas`).

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
3. **Paths** (done): flattening, convex and band tessellation under both
   fill rules, the fringe, the stroker with joins, caps and dashes,
   polygons and polylines, the mesh pipeline, and `examples/paths.goose`.
   Retained meshes and SVG path data are left for later.
4. **Text** (done): the stb_truetype layer, the vendored Inter subset, the
   SDF atlas, measuring and layout (alignment, baselines, wrapping,
   kerning, fallbacks), outlines, the API check, and `examples/text.goose`.
   Glow and a bitmap mode for small text are left for later.
5. **Clip and layers** (done): analytic and path clips, layers with group
   opacity, every blend mode, blur and drop shadows, `box_shadow`,
   multisampled frames, and `examples/layers.goose`.
6. **Polish** (done): the camera and hit testing, pixel-art mode
   (`antialias`, `pixel_canvas`), statistics, the showcase with its
   window test runner, `examples/pixel_art.goose`, and `docs/gfx2d.md`.

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
