// gfx2d's text without a GPU: the built-in font and its metrics, UTF-8,
// glyphs and kerning, measuring, wrapping and alignment's line widths, and
// fallback fonts. Widths are rounded to a hundredth of a pixel.
import std;
import vec;
import math;
import gfx2d from "../..";

fn r(x: f64) -> f64 { round(x * 100) / 100 }

fn main() {
    let f = gfx2d::default_font();
    print("built-in: valid ", gfx2d::is_valid(f), ", metrics ", gfx2d::metrics_of(f));
    print("at 32px: ascent ", r(gfx2d::font_ascent(f, 32)), ", descent ", r(gfx2d::font_descent(f, 32)),
          ", line height ", r(gfx2d::font_line_height(f, 32)));

    // UTF-8: one to four bytes, and bytes that begin nothing.
    let s = "aé—😀";
    var cps: u32[>..] = [];
    var i = 0;
    while i < s.len {
        let cp, next = gfx2d::decode_utf8(s, i);
        cps.push(cp);
        i = next;
    }
    print("decoded: ", cps);
    let bad: u8[4] = [0x61, 0xC3, 0x28, 0xFF];
    cps.resize(0);
    i = 0;
    while i < bad.len {
        let cp, next = gfx2d::decode_utf8(bad, i);
        cps.push(cp);
        i = next;
    }
    print("invalid: ", cps);

    // Glyphs: the font has Latin, not CJK.
    print("glyphs: A ", gfx2d::glyph_index(f, 'A') != 0, ", é ", gfx2d::glyph_index(f, 0xE9) != 0,
          ", 中 ", gfx2d::glyph_index(f, 0x4E2D) != 0);
    // Kerning pulls A and V together.
    let a = gfx2d::glyph_index(f, 'A');
    let v = gfx2d::glyph_index(f, 'V');
    print("kerning AV: ", gfx2d::kern(f, a, v) < 0, ", AA: ", gfx2d::kern(f, a, a));

    // Measuring.
    let one = gfx2d::measure_text("Hello", 32);
    let two = gfx2d::measure_text("Hello\nworld", 32);
    print("Hello at 32: ", r(one.x), " x ", r(one.y), "; two lines: ", r(two.y), " high");
    print("twice the size, twice as wide: ", r(gfx2d::measure_text("Hello", 64).x) == r(2 * one.x));
    let av = gfx2d::measure_text("AV", 32).x;
    let a_alone = gfx2d::measure_text("A", 32).x;
    let v_alone = gfx2d::measure_text("V", 32).x;
    print("AV narrower than A and V: ", av < a_alone + v_alone);
    let spaced = gfx2d::measure_text("Hello", gfx2d::TextStyle { size: 32, letter_spacing: 2 }).x;
    print("letter spacing adds 4 x 2: ", r(spaced - one.x));
    print("empty: ", gfx2d::measure_text("", 32));

    // Wrapping at spaces, to fit.
    let style = gfx2d::TextStyle { size: 16, wrap_width: 100 };
    let text = "the quick brown fox jumps over the lazy dog";
    var lines: u8[][>..] = [];
    gfx2d::each_line(text, style) { from, to => lines.push(text[from..to]); };
    print("wrapped: ", lines.len, " lines: ", lines);
    var fits = true;
    for line in lines {
        if gfx2d::line_width(line, 0, line.len, style) > 100 { fits = false; }
    }
    print("each fits: ", fits, "; measured height ", r(gfx2d::measure_text(text, style).y), " = ",
          lines.len, " x ", r(gfx2d::font_line_height(f, 16)));
    // A long paragraph, greedily: every line fits, and none could take the
    // next line's first word too.
    var para: u8[>..] = [];
    for k in 30 { para.append("Sphinx of black quartz, judge my vow; waltz, nymph, for quick jigs vex Bud. "); }
    let narrow = gfx2d::TextStyle { size: 15, wrap_width: 230, letter_spacing: 0.5 };
    var starts: i64[>..] = [];
    var ends: i64[>..] = [];
    gfx2d::each_line(para, narrow) { from, to => starts.push(from); ends.push(to); };
    var greedy = true;
    for k in starts.len {
        if gfx2d::line_width(para, starts[k], ends[k], narrow) > 230 { greedy = false; }
        if k + 1 < starts.len {
            var next_end = starts[k + 1];
            while next_end < para.len && para[next_end] != ' ' { next_end++; }
            if gfx2d::line_width(para, starts[k], next_end, narrow) <= 230 { greedy = false; }
        }
    }
    print("long paragraph: ", starts.len, " lines, each full and fitting ", greedy);
    var long_word: u8[>..] = [];
    gfx2d::each_line("a supercalifragilistic b", gfx2d::TextStyle { size: 16, wrap_width: 30 }) { from, to =>
        long_word.append(str(to - from, " "));
    };
    print("a word wider than the wrap: line lengths ", long_word);

    // Fallbacks: the same font as its own fallback is refused; a second
    // copy of it is a fallback, and its glyphs are found through it.
    let copy = gfx2d::font_from_memory(embed_file("../../third_party/fonts/Inter-Regular-subset.ttf"));
    gfx2d::add_fallback(f, f);
    gfx2d::add_fallback(f, copy);
    let gf, g = gfx2d::resolve_glyph(copy, 'x');
    print("fallback: ", gfx2d::font_entries[gfx2d::entry_of(f)].fallback == copy, ", resolved in ",
          if gf == copy { "itself" } else { "another" }, ", ", g != 0);
    let missing_font, missing = gfx2d::resolve_glyph(f, 0x4E2D);
    print("missing everywhere: .notdef of the first, ", missing == 0 && missing_font == f);
    let nothing, ok = gfx2d::load_font("no such font.ttf");
    print("no file: ", ok, " ", nothing.id);
    print("not a font: ", gfx2d::font_from_memory("not a font").id, ", count ", gfx2d::font_count("not a font"));
    gfx2d::release(copy);
    print("released: ", gfx2d::is_valid(copy), ", fallback cleared ",
          gfx2d::font_entries[gfx2d::entry_of(f)].fallback.id == 0);

    // The atlas, kept small: once full, it keeps every glyph where it is
    // (the frame's instances name those places) and places no more, and at
    // the next frame it starts over and places what was missing.
    gfx2d::atlas_max_h = 256;
    gfx2d::reset_atlas();
    let a = gfx2d::glyph_slot(f, gfx2d::glyph_index(f, 'A'));
    var placed = 0;
    var missing: i32 = 0;
    var cp: u32 = 0x21;
    while !gfx2d::atlas_full && cp < 0x180 {
        let g = gfx2d::glyph_index(f, cp);
        if g != 0 {
            if gfx2d::glyph_slot(f, g).w > 0 { placed++; } else { missing = g; }
        }
        cp++;
    }
    var later: i32 = 0;
    while later == 0 && cp < 0x180 {
        later = gfx2d::glyph_index(f, cp);
        cp++;
    }
    let again = gfx2d::glyph_slot(f, gfx2d::glyph_index(f, 'A'));
    print("atlas full: ", gfx2d::atlas_full, " after more than 50 glyphs ", placed > 50, "; A kept ",
          again.x == a.x && again.y == a.y && again.w == a.w, "; the one that did not fit not placed ",
          gfx2d::find_slot(gfx2d::glyph_key(f, missing)) < 0, ", nor one after it ",
          gfx2d::glyph_slot(f, later).w == 0 && gfx2d::find_slot(gfx2d::glyph_key(f, later)) < 0);
    gfx2d::begin_atlas_frame();
    print("next frame: starts over ", gfx2d::atlas_h == 0 && !gfx2d::atlas_full, ", the missing glyph placed ",
          gfx2d::glyph_slot(f, missing).w > 0, ", and the later one ", gfx2d::glyph_slot(f, later).w > 0);
    gfx2d::atlas_max_h = 4096;
    gfx2d::reset_atlas();
}
