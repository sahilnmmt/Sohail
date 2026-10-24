/*
 * Minimal band-clipped drawing helpers for overlays (text, status dots).
 * All functions draw into a band buffer covering screen rows
 * [y0, y0 + rows) and silently clip anything outside it.
 */
#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint16_t *buf;
    int width;   /* screen width == band stride */
    int y0;      /* first screen row in the band */
    int rows;
    bool swap_bytes;
} gfx_band_t;

#define GFX_FONT_W 5
#define GFX_FONT_H 7
#define GFX_FONT_ADVANCE 6 /* glyph width + 1 column spacing */

void gfx_fill_rect(const gfx_band_t *b, int x, int y, int w, int h, uint16_t color);
void gfx_fill_circle(const gfx_band_t *b, int cx, int cy, int r, uint16_t color);
/* Draws ASCII text; any other character (UTF-8 code point) renders as one
 * '?'. Returns the x after the text. */
int gfx_text(const gfx_band_t *b, int x, int y, int scale, uint16_t color, const char *s);
int gfx_text_width(const char *s, int scale);
/* Draws text centred horizontally on the screen. */
void gfx_text_centered(const gfx_band_t *b, int y, int scale, uint16_t color, const char *s);

/*
 * Greedy word wrap: splits s into at most max_lines lines of at most
 * max_chars characters, written into lines[i] (each max_chars + 1 bytes).
 * Returns the number of lines; text that does not fit ends with "..".
 */
int gfx_wrap(const char *s, int max_chars, char *lines, int max_lines);

/* 5x7 glyph columns for ASCII 0x20..0x7E, LSB = top row. */
extern const uint8_t gfx_font5x7[95][5];

#ifdef __cplusplus
}
#endif
