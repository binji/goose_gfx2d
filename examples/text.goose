// gfx2d's text: sizes, alignment, wrapping, paints on text, outlines,
// turning and scaling, and a font of the program's own.
//
//   goose examples/text.goose
//   goose examples/text.goose -- --frames 60 --screenshot text.png --font path/to/font.ttf
//
// Escape or closing the window quits.
import std;
import vec;
import math;
import os;
import gfx;
import gfx2d from "..";

fn main() {
    var frames = -1;
    var screenshot: u8[>..] = [];
    var font_path: u8[>..] = [];
    let argv = args();
    var i = 1;
    while i + 1 < argv.len {
        if argv[i] == "--frames" {
            let n, ok = parse_int(argv[i + 1]);
            if ok { frames = n; }
        } else if argv[i] == "--screenshot" {
            screenshot.append(argv[i + 1]);
        } else if argv[i] == "--font" {
            font_path.append(argv[i + 1]);
        }
        i += 2;
    }
    guard gfx::open("gfx2d: text", 800, 600, gfx::WINDOW_RESIZABLE) else {
        write_stderr(str("gfx: ", gfx::error(), "\n"));
        return;
    }
    // A font of the program's, if given, for the headline.
    var headline_font = gfx2d::default_font();
    if font_path.len > 0 {
        let f, ok = gfx2d::load_font(font_path);
        if ok { headline_font = f; } else { write_stderr(str("no font at ", font_path, "\n")); }
    }

    let ink = gfx2d::rgb(0x1D3557);
    let paper = gfx2d::rgb(0xF1FAEE);
    let accent = gfx2d::rgb(0xE63946);
    let story = "Goose is a memory-safe systems language with no heap allocator, garbage collector, or lifetime annotations. Every dynamic value lives inline on a data stack.";
    var drawn = 0;
    while gfx::frame() {
        if gfx::key_pressed("Escape") || drawn == frames { break; }
        let t: f64 = drawn / 60.0;
        gfx2d::frame(paper) {
            // A headline in a gradient, with an outline behind it.
            let headline = gfx2d::TextStyle { font: headline_font, size: 56 };
            var outlined = headline;
            outlined.outline = 6;
            gfx2d::text(30, 20, "gfx2d text", outlined, gfx2d::rgb(0xA8DADC));
            gfx2d::text(30, 20, "gfx2d text", headline,
                        gfx2d::linear(30, 0, 330, 0, accent, gfx2d::rgb(0x457B9D)));

            // Sizes from 8 to 32 pixels.
            var y = 100.0;
            for size in [8, 10, 12, 14, 16, 20, 24, 32] {
                gfx2d::text(30, y, str(size, "px  The quick brown fox jumps over the lazy dog."), size, ink);
                y += size * 1.35;
            }

            // Wrapped to a column, each alignment; the column's edges drawn.
            for k in 3 {
                let x = 30.0 + k * 250;
                let anchor = x + 5 + 105.0 * k;
                gfx2d::rect_outline(x, 380, 220, 150, 1, gfx2d::fade(ink, 0.3));
                gfx2d::text(anchor, 388, story, gfx2d::TextStyle { size: 14, align: k as i32,
                                                                 wrap_width: 210, line_spacing: 1.1 }, ink);
            }

            // Turning, and scaled under the transform, about its middle.
            gfx2d::translate(640, 200) {
                gfx2d::rotate(t * 0.5) {
                    gfx2d::text(0, 0, "turning", gfx2d::TextStyle { size: 28, align: gfx2d::ALIGN_CENTER,
                                                                    baseline: gfx2d::BASELINE_MIDDLE }, accent);
                };
            };
            gfx2d::translate(640, 300) {
                gfx2d::scale(1 + 0.5 * sin(t * 2), 1) {
                    gfx2d::text(0, 0, "stretch", gfx2d::TextStyle { size: 24, align: gfx2d::ALIGN_CENTER,
                                                                    baseline: gfx2d::BASELINE_MIDDLE }, ink);
                };
            };
            // The measured box of a word, drawn behind it.
            let word = "measured";
            let box = gfx2d::measure_text(word, 20);
            gfx2d::rounded_rect(30 - 4, 560 - 2, box.x + 8, box.y + 4, 4, gfx2d::rgb(0xA8DADC));
            gfx2d::text(30, 560, word, 20, ink);
            gfx2d::text(770, 560, "Ünïcödé — café, naïve, 25 °C, €9.99 →", gfx2d::TextStyle {
                size: 16, align: gfx2d::ALIGN_RIGHT }, ink);
        };
        drawn++;
    }
    if screenshot.len > 0 { gfx::screenshot(screenshot); }
    gfx::close();
}
