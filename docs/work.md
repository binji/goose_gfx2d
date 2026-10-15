# gfx2d: work to do

A review of the library after its six phases, as a list of changes, each
small enough to review as one commit. They are in the order to do them:
bugs first, then the costs the benchmarks (`bench/results.md`) point at,
then the API and packaging. Each item says what is wrong, what to change,
and how to check it. Strike items out as they land.

## Bugs

1. ~~**The glyph atlas overflow corrupts the frame it happens in.**~~ Done. When
   `pack` finds no room, `glyph_slot` (`text.goose`) resets the atlas and
   packs the glyph into the empty one, but instances recorded earlier in
   the frame still name the old places in the atlas, and the texture is
   rebuilt from the new pixels at `end()`. Text drawn before the overflow
   comes out as other glyphs, and an app with enough glyphs in use (CJK,
   several fonts) can overflow every frame.
   *Change:* on overflow, draw nothing for that glyph, remember that the
   atlas is full, and reset it at the next `begin()`, before any glyph of
   the new frame is placed. Say so once on stderr. Make the atlas's height
   limit a variable so a test can lower it.
   *Check:* a pure test that lowers the limit, draws more glyphs than fit
   in one frame, and sees the earlier glyphs' slots unchanged, then the
   reset at the next frame.

2. ~~**The texture pool never shrinks.**~~ Done. `pooled` (`gfx2d.goose`) matches on
   exact size, so every window resize leaves the old target-sized layer,
   mask and multisample textures allocated for good. A resize drag with one
   layer in the frame accumulates hundreds of megabytes.
   *Change:* count the frames each pooled texture has gone unused, and
   release it after a few. *Check:* a headless test that draws a layer at
   two sizes and reads the pool's length after some frames.

3. ~~**`image()` takes a `tint: Color` only**~~ Done (as `Paint` overloads
   beside the `Color` ones, since a parameter with a default needs a type;
   the paint's space stays local). So an image could not be drawn
   with a blend mode or a paint's opacity, though the comment above it says
   it takes those "like any shape".
   *Change:* make `tint` the generic `c` the shapes take: a `Color` tints,
   a `Paint` tints by its color and lends its blend, opacity and space, and
   its own image is replaced. *Check:* a headless case drawing an image in
   `BLEND_ADD` and at half opacity.

4. **A composited layer clamps at its edge** (`composite.frag`): a drop
   shadow with an offset smears the layer's edge pixels across the gap,
   since the layer texture is sampled past its edge with a clamping
   sampler. *Change:* treat samples outside the layer as transparent.
   *Check:* the `shadow` case in `test/headless/layers.goose`, with the
   shadowed shape touching the target's edge.

5. **The docs have drifted.** `docs/design.md` holds every section from
   "Transforms as scopes" through "Paths" twice (the second copy is the
   older sketch, with `alias Path`, `Mesh` and `draw_triangles`), and names
   that never shipped: `set_scale`, `LINEAR_BLENDING`, `crisp()`,
   `HAIRLINE`, `hit_rect`, `SpriteAtlas`. The header of `gfx2d.goose` still
   says "this is its first phase". *Change:* delete the duplicate, mark the
   unshipped names as not done (or move them to the follow-ups), and fix
   the header. No code.

## Performance

6. **Gradient ramps are baked and uploaded again every frame.** The
   `gradients` case spends 44 ms baking 2,000 ramps that do not change
   between frames, and uploads the whole atlas each frame.
   *Change:* keep the ramp table across frames, keyed by the hash it has
   now, and upload only rows added since the last frame, as the glyph atlas
   does; start over when it fills, the same way. *Check:* `gradients`
   record time near `circles`' after the first frame; `pure_paint` and
   `headless_paint` unchanged.

7. **Paint records are deduplicated against the last one only**
   (`paint_index`). Two paints taking turns make a record per shape:
   `shared_gradients` uploads 10,000 records. A `solid(c)` with an opacity
   also makes a record, though the instance's color could carry it.
   *Change:* a hash table of the frame's paints, like the ramps'; and map a
   paint with no gradient, no image and local space to paint 0, with its
   opacity folded into the instance color's alpha. *Check:* `stats().paints`
   in the `shared` case of `headless_paint`, and `shared_gradients`' upload.

8. **Every stroke is outlined and filled by the nonzero sweep.** That is
   what makes `chart` 83 ms and `dashed` 119 ms of record time plus 30 MB
   of upload. The union property only shows with a translucent paint.
   *Change:* for an opaque paint, emit the stroke directly: two triangles a
   segment, the join's triangles, the caps, and a fringe quad along each
   edge; keep the outline-and-sweep for translucent paints and for
   `pixels` strokes under a non-uniform transform if it needs them.
   *Check:* `pure_path`'s stroke areas against the new emitter, and the
   `chart` and `dashed` cases.

9. **Retained meshes.** A path drawn every frame is flattened and
   tessellated every frame. *Change:* `tessellate(path, …) -> Mesh`
   (vertices, indices, the transform it was made under) and
   `draw(mesh, c)`, drawn under the current transform; valid while the
   transform is a similarity of the one it was made under, or always with
   no fringe. *Check:* a pure test that a mesh drawn twice gives the same
   triangles, and `big_path` drawn retained.

10. **The shape fragment shader does per-instance work per fragment.**
    `shape.frag` takes the sine and cosine of the span angle, and the pixel
    size from derivatives, in every fragment, though both are constant per
    instance under an affine transform; and it reads the paint record and
    walks the clip chain when the instance has neither. 10,000 small
    circles take 16 ms of GPU time on an Intel UHD 620.
    *Change:* compute the sine and cosine and the pixel size in
    `shape.vert` and pass them flat; return early from `paint_color` and
    `clip_coverage` for paint 0 and clip 0. *Check:* the headless tests
    pixel for pixel, and `circles`' GPU time.

11. **Layers are the target's size.** Every layer clears, draws and
    composites a full-target texture (8 MB at 1080p), and a blur is up to
    48 taps a pass over all of it. `gfx` has `scissor`.
    *Change:* track the pixel bounds of what a layer's block draws
    (instances' quads, meshes' vertices, nested layers' bounds), grown by
    the blur and shadow, and scissor the layer's clear, its blur passes and
    its composite to that. *Check:* `headless_layers` unchanged;
    `layers`, `blur` GPU times.

12. **A blur at large sigma runs at full resolution.** *Change:* for sigma
    above a few pixels, blur at half or quarter resolution (a downsample
    pass, the two blur passes there, an upsample in the composite), with
    sigma scaled. *Check:* the `blur` case of `headless_layers` keeps its
    total within tolerance; the `blur` benchmark.

13. **Every batch rebinds everything.** `flush_batches` binds the pipeline,
    all textures, both storage buffers and both uniform blocks for each
    batch; `sprites_alternating` pays 8 µs a draw call in `end()`.
    *Change:* remember what is bound in the pass and bind only what
    changed. *Check:* `sprites_alternating`'s `end` time; the tests.

14. **Text layout crosses into C for every glyph.** `each_glyph` calls
    `kern` and `advance_of` (extern) per glyph, `text()` runs `each_line`
    twice, and an aligned line is measured again before it is drawn. 9,000
    glyphs cost 7.6 ms.
    *Change:* keep the advance in `GlyphSlot` (filled when the glyph is
    first seen, with or without a bitmap) and kerning pairs in a small hash
    table; lay each line out once into a per-frame array of placed glyphs
    and draw from that. *Check:* `pure_text` unchanged; `text_page` and
    `text_wrapped` times.

15. **Two quadratic spots in the tessellator.** `fill_side` calls
    `winding_at` over every contour for each contour: O(points × contours),
    which text as paths or a map pays. `band_spans` matches a span to the
    open trapezoids by linear search: O(spans²) a band for a wide path.
    *Change:* for the second, both lists are sorted by x, so walk them
    together. For the first, test the winding against the edges the sweep
    already found at span ends, or at least restrict `winding_at` to the
    contours whose bounds contain the test point. *Check:* `pure_path`
    unchanged; a path of 2,000 small contours timed.

16. **`image()` asks `gfx` for the texture's size on every call.**
    `texture_rect` calls `texture_info` per image; `sprites` draws 10,000.
    *Change:* a small cache by texture id, cleared when `gfx` reopens; or an
    `image` overload that takes the size. *Check:* `sprites`' record time.

## API and packaging

17. **f32 fields in structs the user writes.** `TextStyle.size`,
    `Stroke.width`, `dash`, `LayerDesc`'s numbers and `Stop.offset` are
    `f32`, against the rule that scalars are `f64` so any number passes;
    the logo example needs `as f32` casts. *Change:* `f64` in those structs
    (they do not go to the GPU), narrowed where they are used. *Check:* the
    examples build without casts; the tests.

18. **No high-density support.** The design promised a base scale
    (`frame(clear, scale)`) so a program can draw in logical units on a
    display where `gfx`'s pixels are smaller; nothing shipped. *Change:*
    `set_scale(s)` applied under the identity at `begin()`, `to_local` and
    `mouse_local` dividing it out, and `frame`/`draw_into` taking it.
    *Check:* a headless test drawing at scale 2 and reading pixels.

19. **Small inconsistencies.** `star(cx, cy, n, outer, inner, c)` puts `n`
    third while `regular_polygon(cx, cy, r, n, c)` puts it fourth; and
    `ALIGN_CENTER` with a `wrap_width` centers each line on `x` rather than
    within the wrap box, which is not what CSS users expect. *Change:*
    `star(cx, cy, outer, inner, n, c)`; alignment within `[x, x + wrap_width]`
    when a wrap width is set. Both are breaking, so do them now.
    *Check:* the examples, the showcase, `pure_text`.

20. **The stb submodule is the whole repository** for one header, and a
    clone without `--recursive` builds nothing and fails later with
    undefined `gs_gfx2d_*` symbols. *Change:* vendor `stb_truetype.h`
    (public domain) under `third_party/stb/` with its license, drop the
    submodule, and have CMake fail with a clear message if the header is
    missing. *Check:* a fresh clone builds and runs `examples/text.goose`.
