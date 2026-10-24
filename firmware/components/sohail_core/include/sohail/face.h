/*
 * Procedural animated face.
 *
 * The face is described by a small set of float parameters (eye size, lid
 * shapes, mouth, colour). Each expression is a parameter preset; the animator
 * eases the current parameters towards the target preset and layers blinking,
 * gaze and idle motion on top. The renderer draws any horizontal band of the
 * screen into an RGB565 buffer, so the device can stream bands over SPI
 * without a full frame buffer.
 */
#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    FACE_NEUTRAL = 0,
    FACE_HAPPY,
    FACE_LOVE,
    FACE_LAUGH,
    FACE_SAD,
    FACE_WOW,
    FACE_SLEEPY,
    FACE_EXCITED,  /* new message waiting */
    FACE_THINKING, /* connecting / busy */
    FACE_COUNT,
} face_expr_t;

typedef struct {
    float eye_w, eye_h;   /* eye size, fraction of screen width */
    float radius;         /* corner radius, fraction of the smaller eye side */
    float spacing;        /* centre-to-centre distance, fraction of width */
    float y;              /* eye centre, fraction of height */
    float tilt;           /* >0 lowers inner top corners (sad), <0 angry */
    float smile_lid;      /* 0..1, cuts the lower lid into a ^ shape */
    float heart;          /* >0.5 draws hearts instead of eyes */
    float mouth_w, mouth_h; /* mouth size, fraction of width; h <= 0 hides it */
    float mouth_open;     /* 0 = smile (lower half ellipse), 1 = full "o" */
    float r, g, b;        /* eye colour 0..1 */
} face_params_t;

/* One frame's worth of render inputs, produced by the animator. */
typedef struct {
    face_params_t p;
    float blink;       /* 0 = open, 1 = closed */
    float gaze_x, gaze_y; /* -1..1 */
    float bob;         /* vertical offset in pixels */
} face_frame_t;

typedef struct {
    face_expr_t target;
    face_params_t cur;
    uint32_t last_ms;
    uint32_t next_blink_ms;
    uint32_t blink_start_ms;
    uint32_t next_gaze_ms;
    float gaze_x, gaze_y, gaze_tx, gaze_ty;
    uint32_t rng;
    bool started;
} face_anim_t;

const face_params_t *face_preset(face_expr_t expr);
const char *face_expr_name(face_expr_t expr);

void face_anim_init(face_anim_t *a, face_expr_t initial, uint32_t seed);
void face_anim_set(face_anim_t *a, face_expr_t expr);
/* Advance to now_ms and fill out the frame to render. */
void face_anim_step(face_anim_t *a, uint32_t now_ms, face_frame_t *out);

/*
 * Render rows [y0, y0 + rows) of a screen_w x screen_h face into buf
 * (screen_w * rows pixels, RGB565). swap_bytes stores each pixel big-endian,
 * which is what SPI panels such as the ST7789 expect.
 */
void face_render_band(const face_frame_t *f, uint16_t *buf, int screen_w, int screen_h,
                      int y0, int rows, bool swap_bytes);

static inline uint16_t face_rgb565(uint8_t r, uint8_t g, uint8_t b)
{
    return (uint16_t)(((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3));
}

#ifdef __cplusplus
}
#endif
