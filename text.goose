// gfx2d's text: fonts, measuring and laying out text, and drawing it.
//
//   gfx2d::text(20, 20, "Hello, Goose", 32, gfx2d::BLACK);     // the built-in font
//   let f, ok = gfx2d::load_font("fonts/Serif.ttf");
//   gfx2d::text(20, 80, "Centered", gfx2d::TextStyle { font: f, size: 24,
//                                                      align: gfx2d::ALIGN_CENTER },
//               gfx2d::linear(0, 80, 0, 110, gfx2d::RED, gfx2d::BLUE));
//
// Glyphs are drawn from signed distance fields: each glyph is rasterized
// once, at BASE_SIZE, into an atlas texture as the distance to its outline,
// and drawn at any size, under any transform, as an instance of the shape
// pipeline, its coverage from that distance as a shape's is. So text scales
// and turns smoothly, takes any Paint (gradients, images, blend modes), and
// an outline is the same glyph drawn as a stroke of its distance field.
//
// The fonts are TrueType or OpenType; the C layer under src/text/
// (stb_truetype, text_api.h) loads them and rasterizes glyphs, and
// everything else is here. The built-in font is a Latin subset of Inter
// Regular (third_party/fonts/, SIL Open Font License 1.1); text in other
// scripts needs a font of its own, given as a fallback (add_fallback).
// Each character is one glyph: there is no shaping, so scripts that need it
// (Arabic, Devanagari, ...) do not come out right.

namespace gfx2d;

import std;
import vec;
import math;
import os;
import gfx;
import color;
import transform;
import paint;

// --- the C layer: src/text/text_api.h ----------------------------------------------

struct Font { id: u32 }

// In font units; units_per_em of them make the font's em, its size.
struct FontMetrics { units_per_em: i32, ascent: i32, descent: i32, line_gap: i32 }
struct GlyphMetrics { advance: i32, lsb: i32, x0: i32, y0: i32, x1: i32, y1: i32 }
// A rasterized glyph: w x h, its top left (xoff, yoff) from the pen (y down).
struct GlyphBitmap { w: i32, h: i32, xoff: i32, yoff: i32 }

extern "gs_gfx2d_font_load" fn font_load(ttf: const u8[:], index: i64) -> Font;
extern "gs_gfx2d_font_release" fn font_release(f: Font);
extern "gs_gfx2d_font_is_valid" fn is_valid(f: Font) -> bool;
// How many fonts a font file (a collection, .ttc, can have several) holds.
extern "gs_gfx2d_font_count" fn font_count(ttf: const u8[:]) -> i64;
extern "gs_gfx2d_font_info" fn font_info_into(f: Font, out: FontMetrics&) -> bool;
extern "gs_gfx2d_font_glyph" fn glyph_index(f: Font, codepoint: u32) -> i32;
extern "gs_gfx2d_glyph_info" fn glyph_info_into(f: Font, glyph: i32, out: GlyphMetrics&) -> bool;
extern "gs_gfx2d_font_kern" fn kern(f: Font, glyph1: i32, glyph2: i32) -> i32;
extern "gs_gfx2d_glyph_sdf" fn glyph_sdf(f: Font, glyph: i32, scale: f32, padding: i32,
                                         on_edge: u8, dist_scale: f32, out: u8[:],
                                         info: GlyphBitmap&) -> bool;

// --- fonts -------------------------------------------------------------------------------

// What gfx2d knows of a loaded font.
struct FontEntry { font: Font, metrics: FontMetrics, fallback: Font }
var font_entries: FontEntry[>..<] = [];
var default_font_handle = Font { 0 };
var builtin_font = Font { 0 };

fn entry_of(f: Font) -> i64 {
    for e, i in font_entries {
        if e.font == f { return i; }
    }
    -1
}

fn register(f: Font) -> Font {
    if f.id == 0 { return f; }
    var m = FontMetrics { 1000, 800, -200, 0 };
    font_info_into(f, m);
    font_entries.push(FontEntry { font: f, metrics: m, fallback: Font { 0 } });
    f
}

// A font from the bytes of a TrueType or OpenType file (the font at `index`
// of a collection), copied; a zero handle if they are not one.
fn font_from_memory(ttf: const u8[:], index: i64 = 0) -> Font { register(font_load(ttf, index)) }

// A font file, or a zero handle and false.
fn load_font(path: const u8[:], index: i64 = 0) -> Font, bool {
    var bytes: u8[>..] = [];
    if !read_file(path, bytes) { return Font { 0 }, false; }
    let f = font_from_memory(bytes, index);
    return f, f.id != 0;
}

// The built-in font: Inter Regular, Latin.
fn builtin() -> Font {
    if builtin_font.id == 0 {
        builtin_font = font_from_memory(embed_file("third_party/fonts/Inter-Regular-subset.ttf"));
    }
    builtin_font
}

// The font text is drawn in when its style names none: the built-in one
// until set_default_font.
fn default_font() -> Font { if default_font_handle.id != 0 { default_font_handle } else { builtin() } }
fn set_default_font(f: Font) { default_font_handle = f; }

// Characters `f` lacks are drawn in `fallback` (and in its fallback, and so
// on), so one font can cover what another does not.
fn add_fallback(f: Font, fallback: Font) {
    let i = entry_of(f);
    if i < 0 { return; }
    // To the end of the chain, not round it.
    var at = i;
    var steps = 0;
    while font_entries[at].fallback.id != 0 && steps < 16 {
        if font_entries[at].fallback == fallback { return; }
        let next = entry_of(font_entries[at].fallback);
        if next < 0 { break; }
        at = next;
        steps++;
    }
    if font_entries[at].font != fallback { font_entries[at].fallback = fallback; }
}

// Frees the font. Glyphs of it already in the atlas stay until it fills.
fn release(f: Font) {
    let i = entry_of(f);
    if i >= 0 {
        font_entries[i].font = Font { 0 };
        for &e in font_entries { if e.fallback == f { e.fallback = Font { 0 }; } }
    }
    if default_font_handle == f { default_font_handle = Font { 0 }; }
    reset_font_caches();
    font_release(f);
}

fn metrics_of(f: Font) -> FontMetrics {
    let i = entry_of(f);
    if i < 0 { return FontMetrics { 1000, 800, -200, 0 }; }
    font_entries[i].metrics
}

// A font's vertical metrics at `size` pixels: how far above the baseline
// its letters go, how far below (negative), and the distance between
// baselines.
fn font_ascent(f: Font, size: f64) -> f64 {
    let m = metrics_of(f);
    m.ascent * size / m.units_per_em
}
fn font_descent(f: Font, size: f64) -> f64 {
    let m = metrics_of(f);
    m.descent * size / m.units_per_em
}
fn font_line_height(f: Font, size: f64) -> f64 {
    let m = metrics_of(f);
    (m.ascent - m.descent + m.line_gap) * size / m.units_per_em
}

// --- the glyph atlas ---------------------------------------------------------------------

// Glyphs are rasterized at this em size, in pixels, with their distance
// field reaching GLYPH_PAD pixels out: an outline can be up to about
// GLYPH_PAD * size / BASE_SIZE pixels wide.
let BASE_SIZE: f32 = 48.0;
let GLYPH_PAD = 6;
let GLYPH_ON_EDGE: u8 = 128;
let GLYPH_DIST_SCALE: f32 = 128.0 / 6.0;     // atlas value per pixel of distance
let ATLAS_W = 1024;
// How tall the atlas may grow; a variable so a test can fill it.
var atlas_max_h = 4096;

// A glyph of a font: its advance (font units), and once it is `placed`,
// where in the atlas, and where its bitmap goes from the pen at
// BASE_SIZE. Placed with w == 0: nothing to draw (a space). A slot is made
// the first time the glyph is measured, and placed the first time it is
// drawn.
struct GlyphSlot { key: u64, x: i32, y: i32, w: i32, h: i32, xoff: f32, yoff: f32,
                   advance: i32 = 0, placed: bool = false }

var glyph_slots: GlyphSlot[>..<] = [];      // open addressing; key 0 is empty
var glyph_count = 0;
var atlas_pixels: u8[>..<] = [];           // ATLAS_W x atlas_h, R8
var atlas_h = 0;
var shelf_x = 0;
var shelf_y = 0;
var shelf_h = 0;
// The rows changed since they were last uploaded, and the texture.
var atlas_dirty_lo = 0;
var atlas_dirty_hi = 0;
var atlas_texture = gfx::Texture { 0 };
var atlas_texture_h = 0;
var atlas_opened: i64 = -1;
var sdf_scratch: u8[>..<] = [];
// Set when a glyph found no room: no more are placed this frame (instances
// drawn so far name places in the atlas as it is, so it cannot start over
// until they are drawn), and it starts over at the next begin().
var atlas_full = false;
var warned_full = false;

fn glyph_key(f: Font, glyph: i32) -> u64 { ((f.id as u64) << 32) | (glyph as u32 as u64) + 1 }

fn slot_hash(key: u64, n: i64) -> i64 { (((key * 0x9E3779B97F4A7C15) >> 32) as i64) & (n - 1) }

fn find_slot(key: u64) -> i64 {
    let n = glyph_slots.len;
    if n == 0 { return -1; }
    var i = slot_hash(key, n);
    loop {
        let k = glyph_slots[i].key;
        if k == key { return i; }
        if k == 0 { return -1; }
        i = (i + 1) & (n - 1);
    }
}

fn insert_slot(s: GlyphSlot) {
    if (glyph_count + 1) * 2 > glyph_slots.len {
        // Twice the room, everything put in again.
        var old: GlyphSlot[>..<] = [];
        for g in glyph_slots { if g.key != 0 { old.push(g); } }
        let n = max(glyph_slots.len * 2, 256);
        glyph_slots.resize(0);
        glyph_slots.resize(n, GlyphSlot { 0, 0, 0, 0, 0, 0.0, 0.0 });
        glyph_count = 0;
        for g in old { place_slot(g); }
    }
    place_slot(s);
}

fn place_slot(s: GlyphSlot) {
    let n = glyph_slots.len;
    var i = slot_hash(s.key, n);
    while glyph_slots[i].key != 0 { i = (i + 1) & (n - 1); }
    glyph_slots[i] = s;
    glyph_count++;
}

// Forgets every glyph: the atlas starts empty again.
fn reset_atlas() {
    glyph_slots.resize(0);
    glyph_count = 0;
    atlas_pixels.resize(0);
    atlas_h = 0;
    shelf_x = 0;
    shelf_y = 0;
    shelf_h = 0;
    atlas_dirty_lo = 0;
    atlas_dirty_hi = 0;
    atlas_full = false;
}

// At a frame's start (gfx2d.goose's begin): an atlas that filled last
// frame starts over, now that what named its glyphs has been drawn.
fn begin_atlas_frame() {
    if atlas_full { reset_atlas(); }
}

// Room for a w x h glyph, on the current shelf or a new one, the atlas
// grown taller if need be: its top left, or false if the atlas is full.
// Full, it stays as it is (its shelves included) until it starts over.
fn pack(w: i64, h: i64) -> i64, i64, bool {
    var x = shelf_x;
    var y = shelf_y;
    var sh = shelf_h;
    if x + w + 1 > ATLAS_W {
        y += sh + 1;
        x = 0;
        sh = 0;
    }
    if y + h + 1 > atlas_h {
        let need = y + h + 1;
        var grown = max(atlas_h, 256);
        while grown < need { grown *= 2; }
        if grown > atlas_max_h { return 0, 0, false; }
        atlas_pixels.resize(ATLAS_W * grown, 0);
        atlas_h = grown;
    }
    shelf_x = x + w + 1;
    shelf_y = y;
    shelf_h = max(sh, h);
    return x, y, true;
}

// Glyph `glyph` of font f in the atlas, rasterized the first time; with
// nothing to draw (w 0) if the atlas is full, until it starts over at the
// next frame.
// The index of the glyph's slot, made with its advance if it has none.
fn slot_index(f: Font, glyph: i32) -> i64 {
    let key = glyph_key(f, glyph);
    let found = find_slot(key);
    if found >= 0 { return found; }
    insert_slot(GlyphSlot { key, 0, 0, 0, 0, 0.0, 0.0, advance_of(f, glyph), false });
    find_slot(key)
}

// The glyph's advance, in font units, from its slot: one call into the
// font for each glyph ever seen.
fn glyph_advance(f: Font, glyph: i32) -> i32 {
    let at = slot_index(f, glyph);
    glyph_slots[at].advance
}

fn glyph_slot(f: Font, glyph: i32) -> GlyphSlot {
    let at = slot_index(f, glyph);
    if glyph_slots[at].placed { return glyph_slots[at]; }
    let key = glyph_slots[at].key;
    let advance = glyph_slots[at].advance;
    if atlas_full { return GlyphSlot { key, 0, 0, 0, 0, 0.0, 0.0, advance, false }; }
    let m = metrics_of(f);
    let scale = BASE_SIZE / m.units_per_em;
    var info = GlyphBitmap { 0, 0, 0, 0 };
    if sdf_scratch.len < 256 * 256 { sdf_scratch.resize(256 * 256, 0); }
    var ok = glyph_sdf(f, glyph, scale, GLYPH_PAD, GLYPH_ON_EDGE, GLYPH_DIST_SCALE, sdf_scratch, info);
    if !ok && info.w * info.h > sdf_scratch.len {
        sdf_scratch.resize(info.w * info.h, 0);
        ok = glyph_sdf(f, glyph, scale, GLYPH_PAD, GLYPH_ON_EDGE, GLYPH_DIST_SCALE, sdf_scratch, info);
    }
    var s = GlyphSlot { key, 0, 0, 0, 0, info.xoff, info.yoff, advance, true };
    if ok && info.w > 0 && info.h > 0 {
        let x, y, room = pack(info.w, info.h);
        if !room {
            // Full. Not placed, so it is at the next frame, once the atlas
            // has started over; unless it would not fit even an empty
            // atlas, which is remembered as nothing to draw.
            if shelf_x == 0 && shelf_y == 0 { glyph_slots[at] = s; return s; }
            atlas_full = true;
            if !warned_full {
                write_stderr("gfx2d: the glyph atlas is full; text needing new glyphs is missing this frame, and the atlas starts over next frame\n");
                warned_full = true;
            }
            s.placed = false;
            return s;
        }
        if room {
            for row in info.h {
                let to = (y + row) * ATLAS_W + x;
                for col in info.w { atlas_pixels[to + col] = sdf_scratch[row * info.w + col]; }
            }
            s.x = x as i32;
            s.y = y as i32;
            s.w = info.w;
            s.h = info.h;
            if atlas_dirty_hi <= atlas_dirty_lo { atlas_dirty_lo = y; atlas_dirty_hi = y + info.h; }
            else {
                atlas_dirty_lo = min(atlas_dirty_lo, y);
                atlas_dirty_hi = max(atlas_dirty_hi, y + info.h);
            }
        }
    }
    glyph_slots[at] = s;
    s
}

// The atlas's texture, with every glyph rasterized so far in it: made
// again when it has grown or gfx was opened again.
fn upload_atlas() -> gfx::Texture {
    if atlas_h == 0 { return gfx::Texture { 0 }; }
    if atlas_opened != gfx::open_count() || atlas_texture_h != atlas_h {
        if atlas_opened == gfx::open_count() && atlas_texture.id != 0 { gfx::release(atlas_texture); }
        atlas_texture = gfx::texture2d(ATLAS_W, atlas_h, gfx::R8, gfx::SAMPLED);
        atlas_texture_h = atlas_h;
        atlas_opened = gfx::open_count();
        gfx::update_texture(atlas_texture, atlas_pixels);
        atlas_dirty_lo = 0;
        atlas_dirty_hi = 0;
    } else if atlas_dirty_hi > atlas_dirty_lo {
        gfx::update_texture(atlas_texture,
                            gfx::Region { y: atlas_dirty_lo as i32, w: ATLAS_W,
                                          h: (atlas_dirty_hi - atlas_dirty_lo) as i32 },
                            atlas_pixels[atlas_dirty_lo * ATLAS_W .. atlas_dirty_hi * ATLAS_W]);
        atlas_dirty_lo = 0;
        atlas_dirty_hi = 0;
    }
    atlas_texture
}

// --- layout --------------------------------------------------------------------------------

// TextStyle.align.
let ALIGN_LEFT = 0;
let ALIGN_CENTER = 1;
let ALIGN_RIGHT = 2;

// TextStyle.baseline: what the y a text is drawn at is.
let BASELINE_TOP = 0;           // the top of the first line
let BASELINE_MIDDLE = 1;        // the middle of all the lines
let BASELINE_ALPHABETIC = 2;    // the first line's baseline
let BASELINE_BOTTOM = 3;        // the bottom of the last line

struct TextStyle {
    font: Font = Font { 0 },        // none: default_font()
    size: f64 = 16.0,               // the em, in pixels
    align: i32 = 0,                 // ALIGN_LEFT: lines from x; CENTER about it; RIGHT to it
    baseline: i32 = 0,              // BASELINE_TOP
    line_spacing: f64 = 1.0,        // times the font's own line height
    letter_spacing: f64 = 0.0,      // pixels added after each character
    wrap_width: f64 = 0.0,          // lines broken at spaces to fit; 0: only at newlines
    outline: f64 = 0.0,             // > 0: the glyphs' outline, this many pixels wide, not the glyphs
}

// The UTF-8 character at s[i], and where the next starts. A byte that does
// not begin a valid character is U+FFFD on its own.
fn decode_utf8(s: const u8[:], i: i64) -> u32, i64 {
    let b0 = s[i] as u32;
    if b0 < 0x80 { return b0, i + 1; }
    var n = 0;
    var cp: u32 = 0;
    if b0 & 0xE0 == 0xC0 { n = 1; cp = b0 & 0x1F; }
    else if b0 & 0xF0 == 0xE0 { n = 2; cp = b0 & 0x0F; }
    else if b0 & 0xF8 == 0xF0 { n = 3; cp = b0 & 0x07; }
    else { return 0xFFFD, i + 1; }
    for k in 1..n + 1 {
        if i + k >= s.len { return 0xFFFD, i + 1; }
        let b = s[i + k] as u32;
        if b & 0xC0 != 0x80 { return 0xFFFD, i + 1; }
        cp = (cp << 6) | (b & 0x3F);
    }
    return cp, i + n + 1;
}

// Two tables of what the fonts answered, so that a line is laid out
// without calling into them: the glyph a character resolves to (through
// the fallbacks), and the kerning of a pair of glyphs. Open addressing,
// u64 keys with 0 empty, u64 values.
var cmap_keys: u64[>..<] = [];
var cmap_vals: u64[>..<] = [];
var cmap_count = 0;
var kern_keys: u64[>..<] = [];
var kern_vals: u64[>..<] = [];
var kern_count = 0;

fn cache_find(keys: const u64[:], key: u64) -> i64 {
    let n = keys.len;
    if n == 0 { return -1; }
    var i = slot_hash(key, n);
    loop {
        let k = keys[i];
        if k == key { return i; }
        if k == 0 { return -1; }
        i = (i + 1) & (n - 1);
    }
}
fn cache_place(keys: u64[>..<]&, vals: u64[>..<]&, key: u64, val: u64) {
    let n = keys.len;
    var i = slot_hash(key, n);
    while keys[i] != 0 { i = (i + 1) & (n - 1); }
    keys[i] = key;
    vals[i] = val;
}
fn cache_insert(keys: u64[>..<]&, vals: u64[>..<]&, count: i64&, key: u64, val: u64) {
    if (count + 1) * 2 > keys.len {
        let old_keys = copy(keys);
        let old_vals = copy(vals);
        let n = max(keys.len * 2, 256);
        keys.resize(0);
        keys.resize(n, 0);
        vals.resize(0);
        vals.resize(n, 0);
        for k, i in old_keys { if k != 0 { cache_place(keys, vals, k, old_vals[i]); } }
    }
    cache_place(keys, vals, key, val);
    count++;
}
// Forgets what the fonts answered: when a font is released, since its id
// may be given to another.
fn reset_font_caches() {
    cmap_keys.resize(0);
    cmap_vals.resize(0);
    cmap_count = 0;
    kern_keys.resize(0);
    kern_vals.resize(0);
    kern_count = 0;
}

// The font of a chain that has the character, and its glyph there: the
// first font's .notdef (glyph 0) if none does.
fn resolve_glyph(f: Font, cp: u32) -> Font, i32 {
    let key = ((f.id as u64) << 32) | (cp as u64) + 1;
    let found = cache_find(cmap_keys, key);
    if found >= 0 {
        let v = cmap_vals[found];
        return Font { (v >> 32) as u32 }, (v & 0xFFFFFFFF) as i32;
    }
    let gf, g = resolve_glyph_slow(f, cp);
    cache_insert(cmap_keys, cmap_vals, cmap_count, key, ((gf.id as u64) << 32) | (g as u32 as u64));
    return gf, g;
}
fn resolve_glyph_slow(f: Font, cp: u32) -> Font, i32 {
    var at = f;
    var steps = 0;
    while at.id != 0 && steps < 16 {
        let g = glyph_index(at, cp);
        if g != 0 { return at, g; }
        let i = entry_of(at);
        if i < 0 { break; }
        at = font_entries[i].fallback;
        steps++;
    }
    return f, 0;
}

fn advance_of(f: Font, glyph: i32) -> i32 {
    var gm = GlyphMetrics { 0, 0, 0, 0, 0, 0 };
    glyph_info_into(f, glyph, gm);
    gm.advance
}

// The kerning between two glyphs of f (font units), from the table.
fn kern_of(f: Font, g1: i32, g2: i32) -> i32 {
    let key = ((f.id as u64) << 32) | ((g1 as u32 as u64) << 16) | (g2 as u32 as u64) + 1;
    let found = cache_find(kern_keys, key);
    if found >= 0 { return (kern_vals[found] as u32) as! i32; }
    let k = kern(f, g1, g2);
    cache_insert(kern_keys, kern_vals, kern_count, key, k as u32 as u64);
    k
}

fn style_font(style: TextStyle) -> Font { if style.font.id != 0 { style.font } else { default_font() } }

// Every glyph of s[from..to] on one line, from pen x 0: F(font, glyph, x)
// for each, with x in pixels; the line's width.
fn each_glyph<F>(s: const u8[:], from: i64, to: i64, style: TextStyle) -> f64 {
    let f = style_font(style);
    var x = 0.0;
    var prev_font = Font { 0 };
    var prev_glyph: i32 = -1;
    var k = 0.0;            // pixels per font unit of prev_font
    var i = from;
    while i < to {
        let cp, next = decode_utf8(s, i);
        i = next;
        let gf, g = resolve_glyph(f, cp);
        if gf != prev_font { k = style.size / metrics_of(gf).units_per_em; }
        if prev_glyph >= 0 && prev_font == gf { x += kern_of(gf, prev_glyph, g) * k; }
        F(gf, g, x);
        x += glyph_advance(gf, g) * k + style.letter_spacing;
        prev_font = gf;
        prev_glyph = g;
    }
    // No spacing after the last character.
    if to > from { x -= style.letter_spacing; }
    x
}

fn line_width(s: const u8[:], from: i64, to: i64, style: TextStyle) -> f64 {
    let w = each_glyph(s, from, to, style) { f, g, x => };
    w
}

// The lines of s as `style` breaks them: F(from, to) for each, in order.
// Newlines end lines; with a wrap width, so does the last space before a
// line would be wider, and the spaces there are on neither line. A word
// wider than the wrap width has a line of its own and is not broken.
//
// Each word is measured once, and a line's width summed from its words and
// the spaces between them; that leaves out kerning across the spaces, so a
// line that comes within a margin of the wrap width is measured whole.
fn each_line<F>(s: const u8[:], style: TextStyle) {
    let margin = style.size * 0.1 + 2.0;
    var start = 0;
    while start <= s.len {
        var end = start;
        while end < s.len && s[end] != '\n' { end++; }
        if style.wrap_width <= 0.0 {
            F(start, end);
        } else {
            var a = start;          // the line's start
            var fit = -1;           // the end of its last word, -1 before its first
            var w = 0.0;            // the width of s[a..fit], near enough
            var j = start;
            loop {
                var ws = j;
                while ws < end && s[ws] == ' ' { ws++; }
                if ws >= end { break; }
                var we = ws;
                while we < end && s[we] != ' ' { we++; }
                // Each piece's width less the letter spacing after its last
                // character, which the line has.
                let gap_from = if fit < 0 { a } else { fit };
                let gap = if ws > gap_from { line_width(s, gap_from, ws, style) + style.letter_spacing } else { 0.0 };
                let ww = line_width(s, ws, we, style);
                let wider = w + gap + ww;
                if fit >= 0 && wider > style.wrap_width - margin &&
                   (wider > style.wrap_width + margin || line_width(s, a, we, style) > style.wrap_width) {
                    F(a, fit);
                    a = ws;
                    w = ww;
                } else {
                    w = wider;
                }
                fit = we;
                j = we;
            }
            F(a, if fit < 0 { end } else { fit });
        }
        start = end + 1;
    }
}

// s laid out in `style`, once: its lines, each a run of placed glyphs
// (from pen x 0) and a width, in the two arrays below until the next
// layout.
struct PlacedGlyph { font: Font, glyph: i32, x: f32 }
struct LaidLine { first: i64, end: i64, width: f32 }
var placed_glyphs: PlacedGlyph[>..<] = [];
var laid_lines: LaidLine[>..<] = [];
fn layout(s: const u8[:], style: TextStyle) {
    placed_glyphs.resize(0);
    laid_lines.resize(0);
    each_line(s, style) { a, b =>
        let first = placed_glyphs.len;
        let w = each_glyph(s, a, b, style) { gf, g, gx => placed_glyphs.push(PlacedGlyph { gf, g, gx as f32 }); };
        laid_lines.push(LaidLine { first, placed_glyphs.len, w as f32 });
    };
}

// How big s is drawn in `style`: the widest line's width, and the lines'
// height.
fn measure_text(s: const u8[:], style: TextStyle) -> float2 {
    layout(s, style);
    var w: f32 = 0.0;
    for l in laid_lines { w = max(w, l.width); }
    let lh = font_line_height(style_font(style), style.size) * style.line_spacing;
    float2 { w, (laid_lines.len * lh) as f32 }
}
fn measure_text(s: const u8[:], size: f64) -> float2 {
    measure_text(s, TextStyle { size: size as f32 })
}

// --- drawing ------------------------------------------------------------------------------

// s at (x, y), the top left of its first line, `size` pixels, in the
// default font.
fn text(x: f64, y: f64, s: const u8[:], size: f64, c) {
    text(x, y, s, TextStyle { size: size as f32 }, c);
}

// s at (x, y) as `style` lays it out, painted with a Color or a Paint.
fn text(x: f64, y: f64, s: const u8[:], style: TextStyle, c) {
    guard drawing();
    let f = style_font(style);
    let lh = font_line_height(f, style.size) * style.line_spacing;
    let ascent = font_ascent(f, style.size);
    layout(s, style);
    let height = laid_lines.len * lh;
    var baseline = match style.baseline {
        BASELINE_MIDDLE => y - height * 0.5 + ascent,
        BASELINE_ALPHABETIC => y,
        BASELINE_BOTTOM => y - height + ascent,
        _ => y + ascent,
    };
    // On whole pixels where nothing turns the text or scales it unevenly
    // (the base scale is allowed), so its horizontal strokes stay sharp.
    let m = current_transform();
    let plain = m.b == 0.0 && m.c == 0.0 && m.a == m.d && m.a > 0.0;
    let k = (style.size / BASE_SIZE) as f32;
    let stroke = style.outline > 0.0;
    for l in laid_lines {
        var left = x;
        if style.align != ALIGN_LEFT {
            left = if style.align == ALIGN_CENTER { x - l.width * 0.5 } else { x - l.width };
        }
        var line_y = baseline;
        if plain { line_y = (round(line_y * m.a + m.ty) - m.ty) / m.a; }
        for p in placed_glyphs[l.first..l.end] {
            let slot = glyph_slot(p.font, p.glyph);
            if slot.w > 0 {
                let hw = slot.w * 0.5;
                let hh = slot.h * 0.5;
                let local = mul(translation(left + p.x + (slot.xoff + hw) * k, line_y + (slot.yoff + hh) * k),
                                scaling(k));
                add(KIND_GLYPH, if stroke { FLAG_STROKE } else { 0 }, local,
                    geom(hw, hh, if stroke { (style.outline as f32) / k } else { 0.0 }, 0.0),
                    geom(slot.x, slot.y, slot.w, slot.h), c);
            }
        }
        baseline += lh;
    }
}
