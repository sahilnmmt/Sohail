#include "sohail/screen.h"

#include <string.h>

#include "sohail/gfx.h"

#define COLOR_TEXT  0xFFFF
#define COLOR_DIM   0x9CF3
#define COLOR_GREEN 0x07E0
#define COLOR_AMBER 0xFD20
#define COLOR_RED   0xF800

/* Centred text on a black strip, so the moving face never runs into it. */
static void backed_text(const gfx_band_t *b, int y, int scale, uint16_t color, const char *text)
{
    int w = gfx_text_width(text, scale);
    if (w == 0) {
        return;
    }
    gfx_fill_rect(b, (b->width - w) / 2 - 3, y - 2, w + 6, GFX_FONT_H * scale + 4, 0x0000);
    gfx_text_centered(b, y, scale, color, text);
}

void screen_init(screen_t *s, int width, int height, uint32_t seed)
{
    memset(s, 0, sizeof(*s));
    s->width = width;
    s->height = height;
    s->body_chars = (width - 16) / (GFX_FONT_ADVANCE * SCREEN_BODY_SCALE);
    if (s->body_chars > SCREEN_BODY_CHARS_MAX) {
        s->body_chars = SCREEN_BODY_CHARS_MAX;
    }
    face_anim_init(&s->anim, FACE_THINKING, seed);
}

void screen_begin_frame(screen_t *s, const robot_view_t *view, uint32_t now_ms)
{
    s->view = *view;
    if (strcmp(s->wrapped_src, view->body) != 0) {
        strcpy(s->wrapped_src, view->body);
        /* gfx_wrap packs lines body_chars + 1 bytes apart; spread them into rows. */
        char packed[SCREEN_BODY_LINES * (SCREEN_BODY_CHARS_MAX + 1)];
        s->line_count = gfx_wrap(view->body, s->body_chars, packed, SCREEN_BODY_LINES);
        for (int i = 0; i < s->line_count; i++) {
            strcpy(s->lines[i], packed + i * (s->body_chars + 1));
        }
    }
    face_anim_set(&s->anim, view->face);
    face_anim_step(&s->anim, now_ms, &s->frame);
}

void screen_render_band(const screen_t *s, uint16_t *buf, int y0, int rows, bool swap_bytes)
{
    const robot_view_t *v = &s->view;
    face_render_band(&s->frame, buf, s->width, s->height, y0, rows, swap_bytes);
    gfx_band_t b = {.buf = buf, .width = s->width, .y0 = y0, .rows = rows, .swap_bytes = swap_bytes};

    if (v->title[0]) {
        backed_text(&b, 14, 2, COLOR_TEXT, v->title);
    }
    uint16_t dot = v->cloud_up ? COLOR_GREEN : v->wifi_up ? COLOR_AMBER : COLOR_RED;
    gfx_fill_circle(&b, s->width - 14, 20, 4, dot);

    int y = (int)(s->height * 0.70f);
    if (v->show_code && v->code[0]) {
        backed_text(&b, y, 5, COLOR_TEXT, v->code);
        y += GFX_FONT_H * 5 + 10;
        backed_text(&b, y, 1, COLOR_DIM, v->body);
        return;
    }
    for (int i = 0; i < s->line_count; i++) {
        backed_text(&b, y, SCREEN_BODY_SCALE, i ? COLOR_DIM : COLOR_TEXT, s->lines[i]);
        y += GFX_FONT_H * SCREEN_BODY_SCALE + 4;
    }
}
