# gfx2d: future work

Features to add, as a list of changes, each small enough to review as one
commit. Each item says what is missing, what to change, and how to check
it. Strike items out as they land.

Some overlap the follow-ups at the end of [gfx2d.md](gfx2d.md) (SVG arcs,
bitmap glyphs); they are spelled out here.

## Paths

1. **No `arc_to`.** There is no way to add a circular arc tangent to the
   line from the pen to (x1, y1) and to the line from there to (x2, y2),
   joined to the pen by a line, as the HTML canvas's `arcTo` does. It is
   how rounded corners on arbitrary polylines are drawn.
   *Change:* `arc_to(p: Path&, x1, y1, x2, y2, r)` in `path.goose`, built
   on `arc`: find the two tangent points and the center from the corner's
   half-angle, `line_to` the first, and arc to the second the short way
   round. With no pen, it is a `move_to(x1, y1)`; with the three points
   collinear, or `r` zero, a `line_to(x1, y1)`. *Check:* `test/pure/path.goose`:
   a square's corners rounded by `arc_to` have the area of
   `rounded_rect`'s, and the degenerate cases add one line.

2. **`svg_path` refuses elliptical arcs (`A`, `a`).** Most SVG exported
   from editors uses them, so a real icon often fails to parse.
   *Change:* parse `rx ry rotation large-arc sweep x y`, the flags also
   packed without separators (`a1 1 0 00 1 1`), and convert from endpoint
   to center form as the SVG spec's appendix F.6.5 does: radii scaled up
   when too small to reach, a zero radius a line, a zero-length arc
   nothing. Emit cubics of at most a quarter turn, as `arc` does, through
   the rotation. *Check:* pure tests parsing arcs with each flag
   combination, compared with the same arcs built by `arc` and
   `transform`; a path of half-circle arcs with the area of a circle.

3. **A path's rounded rect has one radius.** The shape `rounded_rect`
   takes a `float4` of radii for each corner, but
   `rounded_rect(p: Path&, …)` takes one, so a tab or a speech bubble
   can't be built as a path to stroke or clip by.
   *Change:* an overload taking `float4` radii in the shape's corner order,
   each clamped to half the shorter side, a zero radius a sharp corner.
   *Check:* pure area tests for mixed radii, and a headless test that the
   path's fill covers the pixels the analytic shape does.

## Text

4. **No glyph positions.** A text field needs each character's byte
   offset and x extent to place a caret, select and map a click to a
   character. `layout` (`text.goose`) has all of this in `placed_glyphs`
   but keeps it.
   *Change:* `glyph_positions(x, y, s, style) -> GlyphPosition[]`, with
   `{ byte, x, min_x, max_x }` for each character as drawn (alignment
   applied), and `byte_at(x, y, s, style, p: float2) -> i64` for the caret
   nearest a point. Keep the byte offset of each `PlacedGlyph` in `layout`
   to do it. *Check:* `test/pure/text.goose`: the extents are increasing,
   the last one ends at `measure_text`'s width, multi-byte UTF-8 offsets
   are right, and kerning and letter spacing move them as they move the
   drawing.

5. **No line breaking of the program's own.** A program that lays out,
   scrolls or edits wrapped text itself needs the rows `text` would draw.
   `each_line` does the breaking but is internal.
   *Change:* `break_lines(s, style) -> TextRow[]`, with
   `{ start, end, next, width }` for each row (`next` past the spaces and
   newline that ended it), from `each_line`. `text` and `measure_text`
   keep using `each_line`, so the rows are the ones drawn. *Check:* a pure
   test that the rows with `wrap_width` agree with what `text` draws (via
   `layout`), that each row is no wider than the wrap width unless it is
   one word, and that newlines and runs of spaces end and start rows
   where they should.

6. **`measure_text` gives a size, not where the text is.** With an
   alignment or a baseline other than the defaults, the program works out
   where the box lands itself.
   *Change:* `text_bounds(x, y, s, style) -> Rect`, the box `text(x, y, s,
   style, …)` draws in, from the same alignment and baseline code as
   `text`. *Check:* a headless test drawing text in each alignment and
   baseline and finding every lit pixel inside the bounds, and the bounds
   no more than a glyph's side bearing larger than the lit pixels.

7. **Small text is soft.** Distance-field glyphs rasterized at a 48 px em
   are blurrier than glyphs rasterized at their size, below about 16 px.
   *Change:* when the text's transform is axis-aligned and the size in
   pixels is under a threshold, rasterize coverage glyphs at that size
   (stb already does, before the distance transform) into the same atlas,
   keyed by size, and draw them as images with pixel-snapped origins.
   *Check:* a headless test comparing a 12 px string's pixels with stb's
   rasterization at 12 px; `text_page` in the benchmark not slower.

## Compositing

8. **Some Porter-Duff operators are missing.** There are source-over
   (`NORMAL`), lighter (`ADD`), copy (`REPLACE`), destination-out
   (`ERASE`) and destination-in (`KEEP`), but not source-in, source-out,
   source-atop, destination-over, destination-atop or xor.
   *Change:* `BLEND_SOURCE_IN`, `SOURCE_OUT`, `SOURCE_ATOP`,
   `DESTINATION_OVER`, `DESTINATION_ATOP` and `XOR` as layer modes in
   `layer.goose` and `composite.frag`. As with `KEEP`, the ones that clear
   the backdrop where the layer is not (`SOURCE_IN`, `SOURCE_OUT`,
   `DESTINATION_ATOP`) composite the whole target, not the layer's
   scissor. *Check:* `test/headless/layers.goose`: each mode against
   values worked out by hand, over a translucent backdrop, inside and
   outside the layer's shape.

## Platforms

9. **Tested on one machine.** gfx2d has run on Linux, Vulkan and an
   Intel UHD 620 only (the table in [gfx2d.md](gfx2d.md#platforms-tested)).
   *Change:* run `test/run_tests.py`, the showcase in a window and the
   benchmarks on Windows (D3D12 and Vulkan), macOS (Metal), and an AMD or
   NVIDIA GPU; fix what differs, and fill in the table. *Check:* the
   table, and the showcase's screenshots matching across platforms within
   a tolerance.
