# goose_gfx2d

2D drawing for the [Goose](https://github.com/aardappel/goose) programming
language, on [goose_gfx](https://github.com/aardappel/goose_gfx). It provides
anti-aliased shapes (rectangles, rounded rectangles, circles, ellipses, arcs,
lines, polygons and Bézier paths), fills and strokes, solid, gradient and
image paints with blend modes, 2D transforms, clipping, color math, and
scalable SDF text. All of it is drawn through `gfx` and SDL3's GPU API.

**Status: phase 1 of [the design](docs/design.md).** Solid-color shapes
(rectangles, rounded rectangles, circles, ellipses, rings, pies, arcs and
lines; filled or outlined), transforms and colors work. Gradients, images,
paths and text come next.

## Using it

```goose
import gfx;
import gfx2d from "binji/goose_gfx2d@v1";

fn main() {
    gfx::open("hello", 800, 600);
    while gfx::frame() {
        gfx2d::frame(gfx2d::WHITE) {
            gfx2d::circle(400, 300, 100, gfx2d::rgb(0xE04040));
        };
    }
}
```

## Layout

| | |
|---|---|
| `gfx2d.goose` | the entry: frames, the current transform, shapes, and the renderer |
| `color.goose`, `transform.goose` | colors, and affine transforms and rectangles: plain Goose, no GPU |
| `src/shaders/` | the GLSL that `gfx2d.goose` embeds with `embed_shader` |
| `examples/` | programs using the package, each a root file |
| `test/run_tests.py` | runs `test/pure/` (no GPU) and `test/headless/` (renders into a texture and reads it back), comparing with `test/expected/` |

All the modules are in `namespace gfx2d`. Planned (see the design): `path.goose`, and `text.goose` with
its C layer under `src/text/`, built by a `gfx2d.build` sidecar and
`CMakeLists.txt` with stb_truetype (`third_party/stb`) and a default font
(`third_party/fonts/`, Inter, OFL 1.1).

## Testing

```bash
python test/run_tests.py --goose path/to/goose      # or GOOSE=..., or goose on the PATH
goose examples/shapes.goose                          # a window
```

Headless tests need a GPU device; without one they are reported skipped.

## License

Apache License 2.0, as Goose and goose_gfx.
