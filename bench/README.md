# gfx2d benchmarks

`bench.goose` draws a representative case of each kind of drawing gfx2d
does, frame after frame, into a 1920x1080 target, headless, and times the
frames. `run_bench.py` builds it ahead of time, runs it, and writes
[results.md](results.md):

```bash
python bench/run_bench.py --goose path/to/goose          # all cases, 60 frames each
python bench/run_bench.py --frames 20 text chart         # some of them
python bench/run_bench.py --jit                          # in-process, as `goose file.goose` runs
goose bench/bench.goose -- --list                        # the cases
```

## What is timed

Each frame is timed in three parts, on Goose's monotonic clock (`clock_ns`):

* **record**: the draw calls, from `begin()` to just before `end()`. This is
  where gfx2d's CPU work happens: building shape instances and paint records,
  baking gradient ramps, flattening and tessellating paths, laying out text,
  and rasterizing glyphs the atlas does not have yet.
* **end**: `end()` itself, which uploads the frame's buffers, ramps and new
  glyph rows and records the pass's draw calls. It is also CPU time,
  dominated by bytes uploaded and by draw calls (batches).
* **gpu**: `gfx::flush()`, which submits the frame and waits until the GPU
  has drawn it. This is a wall-clock wait, so it includes submission and
  scheduling, not only shading. The `empty` case is that fixed cost.

Each case runs five frames untimed (the first frame of a case builds
pipelines, grows buffers and fills the glyph atlas), then `--frames` timed
ones. Each column is the median. Every frame of a case draws the same
thing from the same seeds, so only the timing varies. The table also gives
what the last frame drew: shape instances, mesh triangles, draw calls, and
the bytes `end()` uploaded (instances, mesh vertices and indices, paints).

`end` grows with bytes uploaded faster than in proportion on some drivers:
goose_gfx's `update_buffer` creates a transfer buffer per call, and on
Intel's Linux Vulkan driver allocating tens of megabytes a frame is most of
`end`'s time.

## The cases

They're chosen to cover each path through the library once, at a size
where it shows:

| case | measures |
|---|---|
| `empty` | the fixed cost of a frame: one pass, a submit, a wait |
| `circles`, `mixed_shapes` | analytic shapes: one instance each, one batch; the cost per shape |
| `transformed` | the transform stack: three nested blocks per shape |
| `gradients` | a gradient per shape, each its own stops, kept from frame to frame: the ramp lookup |
| `gradients_fresh` | the same with the ramps forgotten each frame: ramp baking, the first frame's cost |
| `shared_gradients` | many shapes on a few gradients: paint records deduplicated, ramps shared |
| `sprites` | images from one sheet: sub-rects, one batch |
| `sprites_alternating` | the worst batching: a draw call per sprite |
| `path_fills` | many small paths: convex (fan) and not (band tessellation) |
| `big_path` | one large outline: band tessellation at scale |
| `self_crossing` | crossings: the band sweep's splitting at intersections |
| `chart` | long polylines: the stroker and the tessellation of long outlines |
| `dashed` | dashing, round caps, and curves flattened for strokes |
| `text_page` | glyph layout and drawing with a warm atlas |
| `text_wrapped` | word wrapping |
| `text_labels` | short text at many sizes and angles |
| `glyph_raster` | rasterizing glyph distance fields: the first frame of new text |
| `clips` | analytic clips: the clip chain in every fragment |
| `path_clips` | path clips: a mask pass each |
| `layers` | layers: a pass, a pass back and a composite each |
| `blend_layers` | blend modes needing the backdrop: a copy more each |
| `blur` | separable gaussian blur passes over the whole target |
| `box_shadows` | analytic blurred rounded rects |
| `ui_scene` | a mix, as an application's frame might be |
| `ui_scene_msaa` | the same into a 4x multisampled target |

Numbers depend on the machine (`results.md` records it) and are for
comparing gfx2d with itself over time: before and after a change, on the
same machine.
