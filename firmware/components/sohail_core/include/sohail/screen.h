/*
 * Complete screen composition: animated face plus the text overlay (title,
 * status dot, setup code, message body). Shared by the firmware UI task and
 * the simulator, so both draw exactly the same pixels.
 */
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "sohail/face.h"
#include "sohail/robot.h"

#ifdef __cplusplus
extern "C" {
#endif

#define SCREEN_BODY_SCALE     2
#define SCREEN_BODY_LINES     4
#define SCREEN_BODY_CHARS_MAX 40

typedef struct {
    int width, height;
    face_anim_t anim;
    face_frame_t frame;
    robot_view_t view;
    /* Body text, re-wrapped only when it changes. */
    char wrapped_src[SOHAIL_TEXT_MAX + 1];
    char lines[SCREEN_BODY_LINES][SCREEN_BODY_CHARS_MAX + 1];
    int line_count;
    int body_chars;
} screen_t;

void screen_init(screen_t *s, int width, int height, uint32_t seed);
/* Latch the view and advance the face animation; call once per frame. */
void screen_begin_frame(screen_t *s, const robot_view_t *view, uint32_t now_ms);
/* Draw screen rows [y0, y0 + rows) into buf (width * rows RGB565 pixels). */
void screen_render_band(const screen_t *s, uint16_t *buf, int y0, int rows, bool swap_bytes);

#ifdef __cplusplus
}
#endif
