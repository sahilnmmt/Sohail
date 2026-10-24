#include "sohail/gfx.h"

#include <string.h>

static inline uint16_t px_out(const gfx_band_t *b, uint16_t c)
{
    return b->swap_bytes ? (uint16_t)((c >> 8) | (c << 8)) : c;
}

void gfx_fill_rect(const gfx_band_t *b, int x, int y, int w, int h, uint16_t color)
{
    int x0 = x < 0 ? 0 : x;
    int x1 = x + w > b->width ? b->width : x + w;
    int y0 = y < b->y0 ? b->y0 : y;
    int y1 = y + h > b->y0 + b->rows ? b->y0 + b->rows : y + h;
    uint16_t c = px_out(b, color);
    for (int yy = y0; yy < y1; yy++) {
        uint16_t *row = b->buf + (size_t)(yy - b->y0) * b->width;
        for (int xx = x0; xx < x1; xx++) {
            row[xx] = c;
        }
    }
}

void gfx_fill_circle(const gfx_band_t *b, int cx, int cy, int r, uint16_t color)
{
    uint16_t c = px_out(b, color);
    for (int yy = cy - r; yy <= cy + r; yy++) {
        if (yy < b->y0 || yy >= b->y0 + b->rows) {
            continue;
        }
        uint16_t *row = b->buf + (size_t)(yy - b->y0) * b->width;
        int dy = yy - cy;
        for (int xx = cx - r; xx <= cx + r; xx++) {
            int dx = xx - cx;
            if (xx >= 0 && xx < b->width && dx * dx + dy * dy <= r * r) {
                row[xx] = c;
            }
        }
    }
}

/* UTF-8 continuation bytes take no space: each code point draws one glyph. */
static inline bool is_continuation(unsigned char c)
{
    return (c & 0xC0) == 0x80;
}

int gfx_text_width(const char *s, int scale)
{
    int n = 0;
    for (; *s; s++) {
        n += !is_continuation((unsigned char)*s);
    }
    return n ? (n * GFX_FONT_ADVANCE - 1) * scale : 0;
}

int gfx_text(const gfx_band_t *b, int x, int y, int scale, uint16_t color, const char *s)
{
    /* Skip quickly when the whole line is outside the band. */
    if (y + GFX_FONT_H * scale <= b->y0 || y >= b->y0 + b->rows) {
        return x + gfx_text_width(s, scale) + (*s ? scale : 0);
    }
    for (; *s; s++) {
        unsigned char ch = (unsigned char)*s;
        if (is_continuation(ch)) {
            continue;
        }
        if (ch < 0x20 || ch > 0x7E) {
            ch = '?';
        }
        const uint8_t *g = gfx_font5x7[ch - 0x20];
        for (int col = 0; col < GFX_FONT_W; col++) {
            for (int row = 0; row < GFX_FONT_H; row++) {
                if (g[col] & (1u << row)) {
                    gfx_fill_rect(b, x + col * scale, y + row * scale, scale, scale, color);
                }
            }
        }
        x += GFX_FONT_ADVANCE * scale;
    }
    return x;
}

void gfx_text_centered(const gfx_band_t *b, int y, int scale, uint16_t color, const char *s)
{
    gfx_text(b, (b->width - gfx_text_width(s, scale)) / 2, y, scale, color, s);
}

int gfx_wrap(const char *s, int max_chars, char *lines, int max_lines)
{
    int stride = max_chars + 1;
    int n = 0;
    while (*s && n < max_lines) {
        while (*s == ' ' || *s == '\n') {
            s++;
        }
        if (!*s) {
            break;
        }
        /* Find the longest prefix that fits, preferring to break at a space. */
        int len = 0, brk = -1;
        while (s[len] && s[len] != '\n' && len < max_chars) {
            if (s[len] == ' ') {
                brk = len;
            }
            len++;
        }
        bool more = s[len] && s[len] != '\n';
        if (more && s[len] != ' ' && brk > 0) {
            len = brk; /* break at the last space instead of mid-word */
        }
        char *dst = lines + n * stride;
        memcpy(dst, s, (size_t)len);
        dst[len] = '\0';
        while (len > 0 && dst[len - 1] == ' ') {
            dst[--len] = '\0';
        }
        s += len;
        n++;
    }
    while (*s == ' ' || *s == '\n') {
        s++;
    }
    if (*s && n > 0) {
        /* Truncated: mark the last line. */
        char *last = lines + (n - 1) * stride;
        int len = (int)strlen(last);
        if (len > max_chars - 2) {
            len = max_chars - 2;
        }
        last[len] = '.';
        last[len + 1] = '.';
        last[len + 2] = '\0';
    }
    return n;
}
