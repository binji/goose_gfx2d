# gfx2d

2D drawing for Goose, on goose_gfx's `gfx`: shapes, paths, paints, text,
clips and layers, anti-aliased, under any 2D transform. This is the
reference: what there is and how to call it, then how it's built,
tested and measured. [design.md](design.md) is the plan the library was
built from, with the reasoning behind the decisions and what's left for
later.

## Using it

```goose
import gfx;
import gfx2d from "binji/goose_gfx2d@v1";

fn main() {
    gfx::open("hello", 800, 600);
    while gfx::frame() {
        gfx2d::frame(gfx2d::WHITE) {
            gfx2d::circle(400, 300, 100, gfx2d::RED);
            gfx2d::text(20, 20, "Hello, Goose", 32, gfx2d::BLACK);
        };
    }
}
```

**Conventions**
* **Coordinates:** pixels, with y down, as `gfx`'s screen has them.
  Angles are radians, clockwise on the screen. Hues are in turns (0 to 1).
* **Scalar parameters are `f64`**, so integers, `f32` and `f64` all pass;
  so are the numbers in `TextStyle`, `Stroke`, `LayerDesc` and `Stop`.
  Points are `float2`, and structs that go to the GPU are `f32`.
* **Paints:** every shape, path, image and text call takes a `Color` or a
  `Paint` in the same position.
* **Namespace:** everything is in `namespace gfx2d` and is called as
  `gfx2d::name(…)`. Goose resolves `x.f()` only in the caller's
  namespace, so building a path is `gfx2d::move_to(p, x, y)`.
* **Blocks:** scoped state takes a trailing block: `translate(x, y) { … }`,
  `clip_circle(…) { … }`, `layer(…) { … }`. Blocks are compile-time and
  inline, so they cost what the plain calls would.
* **Errors:** misuse, such as drawing outside a frame, an unbalanced
  `pop`, or a layer-only blend mode on a paint, is printed when it
  happens and aborts at `end()`, as `gfx` does.

The examples in `examples/` show each part: `shapes`, `paint`, `paths`,
`text`, `layers`, `pixel_art`, `goose_logo` (the Goose logo from its
SVG, animated by warping its path, with an iridescent gloss) and
`breakout`, a small game whose blocks sink and whose rows come in at the
top: a base scale fitting the window, a blurred additive glow, a scene
blurred behind its pause card, a retained star mesh for the shards, a
dashed danger line, and outlined text. Each takes
`-- --frames N --screenshot file.png`.

## Reference

### Frames

| | |
|---|---|
| `frame(clear, samples = 1) { … }` | draw on the screen, cleared, then `end()`; multisampled when `samples` is 2, 4 or 8 |
| `draw_into(target, clear, samples = 1) { … }` | the same into a texture of the program's (a `COLOR_TARGET`) |
| `begin(target, clear, samples = 1)`, `begin(target)`, `begin_screen(…)`, `end()` | the same without a block; `begin(target)` draws over what's there |
| `stats() -> Stats` | what the last `end()` drew: instances, triangles, draw calls, paints, gradient ramps baked (new that frame), bytes uploaded, passes, clips |

Draws are recorded and drawn at `end()` in a pass of gfx2d's own. `begin`
and `end` therefore go between a program's own `gfx` passes, not inside
one, and 2D can go before or after 3D and `ui`.

### Transforms (`transform.goose`)

| | |
|---|---|
| `struct Affine { a, b, c, d, tx, ty }` | `x' = a x + c y + tx`, `y' = b x + d y + ty` |
| `translation`, `scaling`, `rotation`, `rotation_about`, `skewing` | matrices; `IDENTITY` |
| `mul(m, n)`, `apply(m, p)`, `apply_vector`, `invert(m) -> Affine, bool`, `determinant`, `axis_scales`, `angle_of` | matrix math |
| `translate`, `rotate`, `rotate_about`, `scale`, `skew`, `transform(m)` | change the current transform; with a block, only for the block |
| `push()`, `pop()`, `current_transform()`, `set_transform(m)`, `reset_transform()` | the transform stack |
| `to_local(p)`, `to_pixels(p)`, `mouse_local()` | between pixels and the current transform's space |
| `set_scale(s)`, `current_scale()`, `frame(clear, samples, s)`, `draw_into(target, clear, samples, s)` | the base scale every frame starts from: pixels per unit, for high-density displays |
| `struct Rect { x, y, w, h }`, `rect_of`, `center`, `contains`, `inflate`, `intersect`, `union`, `transformed_bounds`, `fit(src, dst, FIT_*)` | rectangles |
| `in_rect`, `in_rounded_rect`, `in_circle`, `in_ellipse`; `contains(path, p, rule)` | hit testing, in the shape's own space |
| `struct Camera2D { center, zoom, rotation }`, `camera(cam) { … }`, `camera_transform`, `world_to_screen`, `screen_to_world` | a 2D camera |

### Shapes

All of these are analytic: one instance each, anti-aliased from the
shape's distance function, and outlines are centered on the edge.

| fill | outline |
|---|---|
| `rect(x, y, w, h, c)`, `rect(Rect, c)` | `rect_outline(x, y, w, h, width, c)` |
| `rounded_rect(x, y, w, h, r, c)`, with `float4` radii for each corner | `rounded_rect_outline(…, width, c)` |
| `circle(cx, cy, r, c)`, `circle(float2, r, c)` | `circle_outline(…, width, c)` |
| `ellipse(cx, cy, rx, ry, c)` | `ellipse_outline(…, width, c)` |
| `ring(cx, cy, r0, r1, c)`, `pie(cx, cy, r, a0, a1, c)` | `pie_outline(…)`, `arc(cx, cy, r, a0, a1, width, c, cap)` |
| `box_shadow(x, y, w, h, r, blur, c, spread = 0)` | `line(x0, y0, x1, y1, width, c, cap)`, with caps `CAP_BUTT`, `CAP_ROUND`, `CAP_SQUARE` |

### Images

| | |
|---|---|
| `image(tex, x, y, tint, filter)` | the whole texture at its size |
| `image(tex, dst: Rect, tint, filter)` | stretched over `dst` |
| `image(tex, dst, src: Rect, tint, filter)` | a part of it, such as a sprite in a sheet; a negative `dst.w` or `dst.h` flips it |
| `nine_slice(tex, dst, [src,] insets, tint, filter)` | corners at their size, edges stretched, the pieces meeting seamlessly |

`tint` is a `Color`, which multiplies the image, or a `Paint`: its color
or gradient multiplies the image, and its blend mode and opacity apply
(`image(tex, x, y, with_blend(solid(WHITE), BLEND_ADD))`); the paint's own
image is replaced, and its space is local (a `Color` tint draws in the
shape's own space, so that every image of one size from one part of a
texture is one paint record, wherever it is). `filter` defaults to
`FILTER_LINEAR`, or `FILTER_NEAREST` with anti-aliasing off.

### Paints (`paint.goose`)

```goose
struct Paint { color, gradient: Gradient, image: Image, image_mode, opacity, blend, space }
```

| | |
|---|---|
| `solid(c)`, `linear(x0, y0, x1, y1, c0, c1)`, `radial(cx, cy, r, inner, outer)`, `pattern(tex)`, `paint(gradient)`, `paint(image)` | paints in one call |
| `linear_gradient(x0, y0, x1, y1, stops)`, `radial_gradient(cx, cy, r, [fx, fy,] stops)`, `conic_gradient(cx, cy, angle, stops)`, `stop(offset, c)` | gradients of up to 16 stops; `spread` (`PAD`, `REPEAT`, `REFLECT`) and `space` (`INTERPOLATE_SRGB`, `LINEAR`, `OKLAB`) are fields |
| `image_pattern(tex, placement, wrap, filter)` | an image placed by an `Affine`, wrapping `CLAMP`, `REPEAT`, `MIRROR` or `DECAL` |
| `image_mode` | how the image combines with the color or gradient: `IMAGE_MULTIPLY` (the default), `REPLACE`, `ADD`, `MASK` |
| `blend` | `BLEND_NORMAL`, `ADD`, `MULTIPLY`, `REPLACE`; other modes need a layer |
| `space` | `SPACE_LOCAL`, which moves with the shape, `SPACE_SCREEN`, or `SPACE_SHAPE`: the shape's own, its center the origin and unscaled (a path or mesh takes it as `LOCAL`) |
| `with_opacity(p, o)`, `with_blend(p, b)` | a changed copy |

### Paths (`path.goose`)

| | |
|---|---|
| `struct Path`, `move_to`, `line_to`, `quad_to`, `cubic_to`, `close`, `clear`, `arc` | building |
| `rect`, `rounded_rect`, `circle`, `ellipse`, `polygon`, `regular_polygon`, `star` (each on a `Path&`) | closed shapes as subpaths |
| `svg_path(path, d) -> bool` | SVG path data: M, L, H, V, C, S, Q, T, Z, absolute and relative; not arcs (A) |
| `transform(path, m)`, `warp(path) { q => … }`, `bounds(path)`, `contains(path, p, rule)` | an affine transform; any function of every point (for animating a shape) |
| `fill(path, c, rule = NONZERO)` | `NONZERO` or `EVEN_ODD`: holes and self-intersections are handled |
| `stroke(path, width, c)`, `stroke(path, Stroke { width, join, cap, miter_limit, dash, dash_offset, pixels }, c)` | joins `JOIN_MITER`, `ROUND`, `BEVEL`; up to 8 dash lengths; `pixels`: width in pixels under any transform |
| `polygon(points, c)`, `triangle`, `quad`, `polyline(points, width, c, cap, join)`, `polygon_outline`, `regular_polygon(cx, cy, r, n, c)`, `star(cx, cy, outer, inner, n, c)` | shortcuts |
| `tessellate(path, rule, scale, antialias) -> Mesh`, `tessellate_stroke(path, Stroke, scale, once, antialias)`, `draw(mesh, c)` | a path tessellated once, for `scale` pixels a unit, and drawn every frame under the current transform; `once` for a stroke a translucent paint will draw |

### Text (`text.goose`)

| | |
|---|---|
| `text(x, y, s, size, c)`, `text(x, y, s, TextStyle, c)` | UTF-8 text, kerned, in the default font |
| `struct TextStyle { font, size, align, baseline, line_spacing, letter_spacing, wrap_width, outline }` | `ALIGN_LEFT`, `CENTER`, `RIGHT` (about or ending at x, or within the wrap box when there is a `wrap_width`); `BASELINE_TOP`, `MIDDLE`, `ALPHABETIC`, `BOTTOM`; `outline > 0` draws the glyphs' outline |
| `measure_text(s, size or style) -> float2` | width of the widest line, and the lines' height |
| `load_font(path) -> Font, bool`, `font_from_memory(bytes, index)`, `release(font)` | TrueType or OpenType fonts |
| `default_font()`, `set_default_font(f)`, `add_fallback(f, other)` | the built-in Inter (Latin), and chains of fonts for other characters |
| `font_ascent`, `font_descent`, `font_line_height` | vertical metrics at a size |

### Clips and layers (`layer.goose`)

| | |
|---|---|
| `clip_rect(…) { … }`, `clip_rounded_rect(…) { … }`, `clip_circle(…) { … }`, `clip_ellipse(…) { … }` | analytic, anti-aliased, nested, under any transform |
| `clip_path(path, rule) { … }` | by a path, through a mask texture |
| `layer(opacity) { … }`, `layer(LayerDesc { opacity, blend, blur, shadow, shadow_offset, shadow_blur }) { … }` | group opacity, blend modes, gaussian blur, drop shadow |
| layer blend modes | `BLEND_NORMAL`, `ADD`, `MULTIPLY`, `REPLACE`, `SCREEN`, `OVERLAY`, `DARKEN`, `LIGHTEN`, `COLOR_DODGE`, `COLOR_BURN`, `HARD_LIGHT`, `SOFT_LIGHT`, `DIFFERENCE`, `EXCLUSION`, `ERASE`, `KEEP` |

### Pixel art

| | |
|---|---|
| `set_antialias(on)`, `antialias(on) { … }` | off: hard edges, with images sampled nearest by default |
| `pixel_canvas(w, h, clear) { … }` | draw at w × h, then scale up by a whole number into the target, centered |
| `pixel_canvas_fit(w, h) -> Affine`, `to_canvas(p, w, h)` | where the canvas lands, and the mouse in its pixels |

Text a few pixels high, drawn hard-edged from a distance field, isn't
legible. Draw a HUD at the window's resolution outside the canvas, or use
a bitmap font from a sprite sheet.

### Colors (`color.goose`)

| | |
|---|---|
| `struct Color { r, g, b, a }` | sRGB, straight alpha, 0 to 1; `BLACK`, `WHITE`, `TRANSPARENT`, `RED`, … (the CSS basic colors and `ORANGE`) |
| `rgb(0xRRGGBB)`, `rgba(hex, a)`, `rgba8`, `rgbf`, `rgbaf`, `gray`, `hex("#…") -> Color, bool`, `from_u32`, `from_float4` | constructors |
| `hsv`, `hsl`, `oklch` (and their `…a` forms); `to_hsv`, `to_hsl`, `to_oklab`, `from_oklab`, `to_oklch`, `to_linear`, `from_linear`, `to_u32`, `to_float4`, `premultiplied` | conversions |
| `with_alpha`, `fade`, `lighten`, `darken`, `saturate`, `desaturate`, `rotate_hue`, `invert`, `grayscale` | manipulation; lightness and chroma in OKLCh |
| `mix` (OKLab), `mix_srgb`, `mix_linear`, `blend_over`, `luminance`, `contrast_ratio`, `readable_on`, `palette(n, seed)` | mixing and contrast |

## How it's built

```
Goose program ──► gfx2d (Goose: shapes, paints, paths, text layout, passes) ──► gfx (SDL_GPU)
                     └─► src/text (C: stb_truetype, glyph distance fields)
```

* **The modules:**
  * `gfx2d.goose` has the frame, renderer, shapes, images and path
    drawing.
  * `layer.goose` has clips and layers.
  * `text.goose` has fonts, the glyph atlas and layout.
  * `paint.goose`, `path.goose`, `color.goose` and `transform.goose` are
    plain Goose and don't touch the GPU, so their tests need neither a
    GPU nor C.
* **The C layer** (`src/text/`) is nine functions over stb_truetype,
  listed in `text_api.h`:
  * loading fonts, metrics, glyph lookup and kerning (each glyph's,
    pair's and character's answer is kept on the Goose side, so laying
    out text calls into C only for what it has not seen),
  * rasterizing a glyph's distance field. It renders coverage with
    stb's scanline rasterizer, then runs a linear-time Euclidean distance
    transform (as TinySDF does).

  stb is compiled in `static`, so it doesn't clash with Nuklear's copy in
  `ui`. `test/api_check.py` checks the header against `text.goose`. The
  sidecar `gfx2d.build` names the CMake target `goose_gfx2d_package`, which
  the Goose compiler builds the first time a program uses the package.
* **Shaders** (`src/shaders/`, GLSL through `embed_shader`):
  * `shape`: instanced quads pulled from a storage buffer, coloured by
    distance functions (`sdf.glsl`), glyphs and box shadows.
  * `mesh`: tessellated paths.
  * `composite`: layers, including the blend modes that read the backdrop.
  * `blur`: separable gaussian blur, copies, and box downsamples.
  * Shared code: paints (`paint.glsl`) and the clip chain
    (`clip.glsl`, `clip_coverage.glsl`).
* **A frame is passes:**
  * Draw passes over runs of batches, multisampled and resolved or not;
    blur and copy passes for layers.
  * Per frame, the instances (112 bytes), mesh vertices (24 bytes) and
    indices, paints (96 bytes) and clips (64 bytes) are each uploaded once.
    Gradient ramps are kept between frames, a row of a 256-wide atlas
    each, and only new rows are baked and uploaded; a full atlas (4,096
    rows) draws further gradients as their middle color that frame and
    starts over at the next.
  * A batch is one draw call. Shape batches split on blend mode, image and
    mask; mesh batches also on their clip. Within a pass a batch binds only
    what differs from the batch before it (pipeline, textures, buffers,
    uniform blocks).
  * Layer, mask and canvas textures come from a pool kept between frames;
    one unused for eight frames (two, if it is not the target's size) is
    released.
  * A layer's texture is the target's size, but only the pixels its block
    draws, grown by its blur's and shadow's reach, are cleared, blurred and
    composited (gfx's scissor); a block that draws nothing leaves no
    passes. `BLEND_KEEP` composites the whole target, since it clears what
    the layer does not cover.
  * A blur of sigma 5 and up (`BLUR_DOWNSAMPLE_FROM`) runs at half
    resolution, of 10 and up at a quarter: the layer is box-downsampled
    in a pass, blurred there with the sigma scaled (what the box and the
    composite's linear upsample add is taken off it), and upsampled by the
    composite. A blur and a shadow at the same resolution share the
    downsample.
* **Paths:** curves are flattened after the transform, then tessellated:
  * a convex contour becomes a fan with an exact one-pixel fringe;
  * anything else is cut into bands at vertices and crossings, with spans
    by the fill rule merged into trapezoids while their edges continue
    (each span finds its trapezoid through its left edge), plus an
    outward half-pixel fringe, whose side is tested against the contours
    around the point only;
  * an opaque stroke is emitted straight from the line: a quad a segment,
    a fan at each join's outer corner, caps, and a fringe along the edges,
    since where it overlaps itself the second drawing does not show;
  * a translucent stroke becomes an outline, filled by `NONZERO` in pieces
    of about 16 segments, so that it is drawn once where it overlaps
    itself.

  [design.md](design.md) has the details and the reasoning.
* **Text:**
  * Glyphs are rasterized once at a 48 px em into a shelf-packed R8 atlas,
    1024 px wide and up to 4096 tall, of which only changed rows are
    uploaded. If it fills, text needing new glyphs is missing for the rest
    of that frame (a warning says so), and the atlas starts over at the
    next.
  * A glyph is drawn as a shape instance whose distance comes from the
    atlas.
  * The built-in font is a 48 KB Latin subset of Inter 4.1 (OFL 1.1), in
    `third_party/fonts/` with the script that made it.

## Testing

```bash
python test/run_tests.py --goose path/to/goose            # API check, pure and headless tests
python test/window/run_window_test.py --goose …           # the showcase, in a window, JIT and AOT
python test/window/run_window_test.py --goose … --headless
python bench/run_bench.py --goose …                       # bench/results.md
```

* **`test/pure/`** needs no GPU or C. It covers:
  * colors: round trips through every space, and known values;
  * transforms, the camera and hit tests;
  * paints and the ramps baked for them;
  * paths, checked by triangle areas, which are exact however the fill was
    cut: both fill rules, holes, pentagrams, bow ties, every join and cap,
    dashes, stroke pieces covering a stroke exactly once, and the fringe
    facing outward;
  * text: metrics, UTF-8, kerning, measuring, greedy wrapping, fallbacks.
* **`test/headless/`** renders into a texture and reads it back:
  * on pixel boundaries, exact pixels;
  * anti-aliased shapes, paths and clips, by their coverage summed against
    the area they should have;
  * gradients by their values;
  * images, sprites and nine-slices texel by texel;
  * every blend mode against values worked out by hand;
  * blur keeping its total, shadows, text placement against
    `measure_text`, pixel art, multisampling and the camera.

  A machine with no GPU device reports these as skipped.
* **`test/window/`:** the showcase draws one scene using a wide spread of
  the API and checks pixels by readback. `run_window_test.py` runs it
  in-process and built ahead of time, and compares the screenshots.

### Platforms tested

| | Linux (Manjaro, Intel UHD 620, Mesa 26 Vulkan) | Windows | macOS |
|---|---|---|---|
| tests, headless | yes: JIT; showcase JIT and gcc AOT, screenshots identical | not run | not run |
| benchmarks | yes, AOT (`bench/results.md`) | not run | not run |
| showcase in a window | not run | not run | not run |

## Follow-up work

[future_work.md](future_work.md) lists features to add, as changes to
make. Besides those:

* **Batching:**
  * shapes and paths in one pipeline, so they don't break each other's
    batches (the UI scene makes 120 draw calls);
  * a texture array for sprites from several sheets.
* **goose_gfx:** reuse transfer buffers across uploads. It creates one per
  call, which costs more than in proportion to its size on Intel's
  driver.
* **Paths:** a fringe only on the stretches of edges that are fill
  boundaries (faint lines show inside a translucent stroke's
  self-crossings); retained meshes kept on the GPU, in a buffer of
  their own, rather than uploaded each frame; SVG elliptical arcs.
* **Text:** bitmap glyphs for small and pixel-art text; glow; HarfBuzz
  shaping.
* **Layers:** a color matrix filter; layer textures the size of their
  contents (their passes are scissored to them already); scissor for
  axis-aligned rectangle clips.
