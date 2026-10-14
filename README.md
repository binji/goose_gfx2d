# goose_gfx2d

2D drawing for the [Goose](https://github.com/aardappel/goose) programming
language, on [goose_gfx](https://github.com/aardappel/goose_gfx). It provides
anti-aliased shapes (rectangles, rounded rectangles, circles, ellipses, arcs,
lines, polygons and Bézier paths), fills and strokes, solid, gradient and
image paints with blend modes, 2D transforms, clipping, color math, and
scalable SDF text. All of it is drawn through `gfx` and SDL3's GPU API.

**Status: design.** See [docs/design.md](docs/design.md).

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
| `gfx2d.goose`, `color.goose`, `path.goose`, `text.goose` | the modules, all in `namespace gfx2d`; only `text.goose` declares `extern fn`s |
| `gfx2d.build` | the package's sidecar: the CMake target to build, and that its functions run on the main thread only |
| `CMakeLists.txt` | builds the text layer (stb_truetype, stb_rect_pack) as a static library, carried by the target `goose_gfx2d_package` |
| `src/shaders/` | the GLSL that `gfx2d.goose` embeds with `embed_shader` |
| `src/text/` | the text layer; `text_api.h` lists every function `text.goose` declares, and `test/api_check.py` checks the two agree |
| `test/pure/` | color, path and tessellation tests that need no GPU |
| `test/headless/` | render into a texture, read it back, compare |
| `test/window/` | the showcase, which needs a display and a GPU |
| `third_party/stb` | shallow submodule; clone with `--recursive` |
| `third_party/fonts/` | the default font, a Latin subset of Inter Regular, with its license (OFL 1.1) |

## License

Apache License 2.0, as Goose and goose_gfx.
