/* The text layer's C API: every function text.goose reaches through an
   `extern "gs_gfx2d_..." fn`, listed once in GS_GFX2D_TEXT_API, which
   expands into the prototypes below; test/api_check.py checks text.goose
   against the list.

   What crosses is what `extern fn` can pass: scalars, u8[:] as { data, len },
   flat structs by value, and T& as a pointer. Goose structs are packed, so
   the structs here are too, each declared again in text.goose with the same
   fields in the same order.

   The layer is stb_truetype and nothing else: it loads fonts from bytes,
   answers questions about them in font units, and rasterizes one glyph's
   signed distance field into a buffer of the caller's. Packing glyphs into
   an atlas, laying out text and drawing it are text.goose's, through gfx.

   A font is a handle: a slot index in the low 20 bits and a generation
   above it, so a released handle is an error, not a crash; 0 is none. */

#ifndef GS_GFX2D_TEXT_API_H
#define GS_GFX2D_TEXT_API_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#pragma pack(push, 1)

typedef struct { const uint8_t *data; int64_t len; } gs_gfx2d_bytes;    /* const u8[:] */
typedef struct { uint8_t *data; int64_t len; } gs_gfx2d_out_bytes;       /* u8[:] */

typedef struct { uint32_t id; } gs_gfx2d_font;

/* In font units; units_per_em is how many make the font's em. */
typedef struct {
    int32_t units_per_em;
    int32_t ascent;             /* above the baseline: positive */
    int32_t descent;            /* below it: negative */
    int32_t line_gap;
} gs_gfx2d_font_metrics;

typedef struct {
    int32_t advance;            /* how far the pen moves */
    int32_t lsb;                /* left side bearing */
    int32_t x0, y0, x1, y1;     /* the outline's bounds, y up */
} gs_gfx2d_glyph_metrics;

/* A rasterized glyph: w x h bytes, its top left xoff, yoff pixels from the
   pen on the baseline (y down). */
typedef struct {
    int32_t w, h;
    int32_t xoff, yoff;
} gs_gfx2d_glyph_bitmap;

#pragma pack(pop)

#define GS_GFX2D_TEXT_API(X)                                                                   \
    X(gs_gfx2d_font, gs_gfx2d_font_load, (gs_gfx2d_bytes ttf, int64_t index))                 \
    X(void, gs_gfx2d_font_release, (gs_gfx2d_font f))                                         \
    X(uint8_t, gs_gfx2d_font_is_valid, (gs_gfx2d_font f))                                     \
    X(int64_t, gs_gfx2d_font_count, (gs_gfx2d_bytes ttf))                                     \
    X(uint8_t, gs_gfx2d_font_info, (gs_gfx2d_font f, gs_gfx2d_font_metrics *out))          \
    X(int32_t, gs_gfx2d_font_glyph, (gs_gfx2d_font f, uint32_t codepoint))                    \
    X(uint8_t, gs_gfx2d_glyph_info, (gs_gfx2d_font f, int32_t glyph,                       \
                                        gs_gfx2d_glyph_metrics *out))                         \
    X(int32_t, gs_gfx2d_font_kern, (gs_gfx2d_font f, int32_t glyph1, int32_t glyph2))         \
    X(uint8_t, gs_gfx2d_glyph_sdf, (gs_gfx2d_font f, int32_t glyph, float scale,              \
                                    int32_t padding, uint8_t on_edge, float dist_scale,       \
                                    gs_gfx2d_out_bytes out, gs_gfx2d_glyph_bitmap *info))

#define GS_GFX2D_TEXT_DECLARE(ret, name, args) ret name args;
GS_GFX2D_TEXT_API(GS_GFX2D_TEXT_DECLARE)
#undef GS_GFX2D_TEXT_DECLARE

#ifdef __cplusplus
}
#endif

#endif
