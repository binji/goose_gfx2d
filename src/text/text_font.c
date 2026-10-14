/* The text layer: fonts loaded with stb_truetype, by handle, and the
   questions text.goose asks of them. See text_api.h. */

#include "text_api.h"

/* stb_truetype, its implementation here and static, so a program linking
   another copy of it (Nuklear's, in ui) sees no clash. Third-party code:
   its warnings are not ours to act on. */
#if defined(_MSC_VER)
#pragma warning(push, 0)
#elif defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wall"
#pragma GCC diagnostic ignored "-Wextra"
#pragma GCC diagnostic ignored "-Wunused-function"
#endif
#define STB_TRUETYPE_IMPLEMENTATION
#define STBTT_STATIC
#include "stb_truetype.h"
#if defined(_MSC_VER)
#pragma warning(pop)
#elif defined(__GNUC__)
#pragma GCC diagnostic pop
#endif

#include <stdlib.h>
#include <string.h>

#define FONT_INDEX_BITS 20
#define FONT_INDEX_MASK ((1u << FONT_INDEX_BITS) - 1)

typedef struct {
    uint8_t *data;              /* the font file, a copy of the program's bytes */
    stbtt_fontinfo info;
    uint32_t generation;
    int live;
} font_slot;

static font_slot *fonts;
static uint32_t font_slots;

static font_slot *font_get(gs_gfx2d_font f) {
    uint32_t i = f.id & FONT_INDEX_MASK;
    if (f.id == 0 || i >= font_slots) return NULL;
    font_slot *s = &fonts[i];
    if (!s->live || s->generation != (f.id >> FONT_INDEX_BITS)) return NULL;
    return s;
}

int64_t gs_gfx2d_font_count(gs_gfx2d_bytes ttf) {
    if (!ttf.data || ttf.len < 12) return 0;
    int n = stbtt_GetNumberOfFonts(ttf.data);
    return n < 0 ? 0 : n;
}

gs_gfx2d_font gs_gfx2d_font_load(gs_gfx2d_bytes ttf, int64_t index) {
    gs_gfx2d_font none = { 0 };
    if (!ttf.data || ttf.len < 12 || index < 0 || index >= gs_gfx2d_font_count(ttf)) return none;
    uint8_t *data = (uint8_t *)malloc((size_t)ttf.len);
    if (!data) return none;
    memcpy(data, ttf.data, (size_t)ttf.len);
    int offset = stbtt_GetFontOffsetForIndex(data, (int)index);
    stbtt_fontinfo info;
    if (offset < 0 || !stbtt_InitFont(&info, data, offset)) {
        free(data);
        return none;
    }
    /* A free slot, or a new one; slot 0 is never used, so no handle is 0. */
    uint32_t i = 1;
    while (i < font_slots && fonts[i].live) i++;
    if (i >= font_slots) {
        uint32_t n = font_slots < 8 ? 8 : font_slots * 2;
        if (n > FONT_INDEX_MASK) { free(data); return none; }
        font_slot *grown = (font_slot *)realloc(fonts, n * sizeof *fonts);
        if (!grown) { free(data); return none; }
        memset(grown + font_slots, 0, (n - font_slots) * sizeof *fonts);
        fonts = grown;
        if (font_slots == 0) i = 1;
        font_slots = n;
    }
    font_slot *s = &fonts[i];
    s->data = data;
    s->info = info;
    s->generation = (s->generation + 1) & (0xFFFFFFFFu >> FONT_INDEX_BITS);
    if (s->generation == 0) s->generation = 1;
    s->live = 1;
    gs_gfx2d_font f = { (s->generation << FONT_INDEX_BITS) | i };
    return f;
}

void gs_gfx2d_font_release(gs_gfx2d_font f) {
    font_slot *s = font_get(f);
    if (!s) return;
    free(s->data);
    s->data = NULL;
    s->live = 0;
}

uint8_t gs_gfx2d_font_is_valid(gs_gfx2d_font f) { return font_get(f) != NULL; }

uint8_t gs_gfx2d_font_info(gs_gfx2d_font f, gs_gfx2d_font_metrics *out) {
    font_slot *s = font_get(f);
    if (!s) return 0;
    int ascent, descent, line_gap;
    stbtt_GetFontVMetrics(&s->info, &ascent, &descent, &line_gap);
    /* The em: head.unitsPerEm, which stb reads for its em scale. */
    float scale = stbtt_ScaleForMappingEmToPixels(&s->info, 1.0f);
    out->units_per_em = scale > 0 ? (int32_t)(1.0f / scale + 0.5f) : 1000;
    out->ascent = ascent;
    out->descent = descent;
    out->line_gap = line_gap;
    return 1;
}

int32_t gs_gfx2d_font_glyph(gs_gfx2d_font f, uint32_t codepoint) {
    font_slot *s = font_get(f);
    return s ? stbtt_FindGlyphIndex(&s->info, (int)codepoint) : 0;
}

uint8_t gs_gfx2d_glyph_info(gs_gfx2d_font f, int32_t glyph, gs_gfx2d_glyph_metrics *out) {
    font_slot *s = font_get(f);
    if (!s) return 0;
    int advance, lsb, x0 = 0, y0 = 0, x1 = 0, y1 = 0;
    stbtt_GetGlyphHMetrics(&s->info, glyph, &advance, &lsb);
    stbtt_GetGlyphBox(&s->info, glyph, &x0, &y0, &x1, &y1);
    out->advance = advance;
    out->lsb = lsb;
    out->x0 = x0;
    out->y0 = y0;
    out->x1 = x1;
    out->y1 = y1;
    return 1;
}

int32_t gs_gfx2d_font_kern(gs_gfx2d_font f, int32_t glyph1, int32_t glyph2) {
    font_slot *s = font_get(f);
    return s ? stbtt_GetGlyphKernAdvance(&s->info, glyph1, glyph2) : 0;
}

uint8_t gs_gfx2d_glyph_sdf(gs_gfx2d_font f, int32_t glyph, float scale, int32_t padding,
                           uint8_t on_edge, float dist_scale, gs_gfx2d_out_bytes out,
                           gs_gfx2d_glyph_bitmap *info) {
    memset(info, 0, sizeof *info);
    font_slot *s = font_get(f);
    if (!s) return 0;
    int w = 0, h = 0, xoff = 0, yoff = 0;
    unsigned char *sdf = stbtt_GetGlyphSDF(&s->info, scale, glyph, padding, on_edge, dist_scale,
                                           &w, &h, &xoff, &yoff);
    info->w = w;
    info->h = h;
    info->xoff = xoff;
    info->yoff = yoff;
    if (!sdf) return 1;                 /* nothing to draw, as for a space */
    /* Too small a buffer: the size is in info, and nothing is written. */
    if ((int64_t)w * h > out.len) {
        stbtt_FreeSDF(sdf, NULL);
        return 0;
    }
    memcpy(out.data, sdf, (size_t)w * h);
    stbtt_FreeSDF(sdf, NULL);
    return 1;
}
