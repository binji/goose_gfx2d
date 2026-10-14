# goose_gfx2d

2D drawing for the [Goose](https://github.com/aardappel/goose) programming
language, on [goose_gfx](https://github.com/aardappel/goose_gfx). It provides
anti-aliased shapes (rectangles, rounded rectangles, circles, ellipses, arcs,
lines, polygons and Bézier paths), fills and strokes, solid, gradient and
image paints with blend modes, 2D transforms, clipping, color math, and
scalable SDF text. All of it is drawn through `gfx` and SDL3's GPU API.

**Status: phases 1 to 4 of [the design](docs/design.md).** These work:
- shapes (rectangles, rounded rectangles, circles, ellipses, rings, pies,
  arcs and lines; filled or outlined),
- transforms and colors,
- paints (linear, radial and conic gradients, images, sprites,
  nine-slices, patterns, gradients blended with images, four blend modes),
- paths (Bézier curves, nonzero and even-odd fills, strokes with joins,
  caps and dashes, polygons, polylines),
- text (TrueType/OpenType fonts, a built-in Inter, SDF glyphs at any size
  and transform, kerning, alignment, wrapping, outlines, any paint).

Clipping and layers come next.

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
| `gfx2d.goose` | the entry: frames, the current transform, shapes, images, paths' drawing, and the renderer |
| `color.goose`, `transform.goose`, `paint.goose`, `path.goose` | colors; affine transforms and rectangles; paints and gradient ramps; paths, tessellation and stroking: plain Goose, no GPU |
| `text.goose` | fonts, the glyph atlas, layout and drawing text |
| `gfx2d.build` | the package's sidecar: the CMake target to build, and that its functions run on the main thread only |
| `CMakeLists.txt` | builds the text layer (stb_truetype) as a static library, carried by the target `goose_gfx2d_package` |
| `src/shaders/` | the GLSL that `gfx2d.goose` embeds with `embed_shader` |
| `src/text/` | the text layer; `text_api.h` lists every function `text.goose` declares, and `test/api_check.py` checks the two agree |
| `examples/` | programs using the package, each a root file |
| `test/run_tests.py` | runs the API check, `test/pure/` (no GPU) and `test/headless/` (renders into a texture and reads it back), comparing with `test/expected/` |
| `third_party/stb` | shallow submodule; clone with `--recursive` |
| `third_party/fonts/` | the built-in font, a Latin subset of Inter Regular, its license (OFL 1.1), and the script that made it |

All the modules are in `namespace gfx2d`.

## Testing

```bash
python test/run_tests.py --goose path/to/goose      # or GOOSE=..., or goose on the PATH
goose examples/shapes.goose                          # a window
```

Headless tests need a GPU device; without one they are reported skipped.

## License

Apache License 2.0, as Goose and goose_gfx. stb is public domain (or MIT);
Inter is under the SIL Open Font License 1.1 (`third_party/fonts/OFL.txt`).
