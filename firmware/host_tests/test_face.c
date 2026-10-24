#include "sohail/face.h"
#include "test.h"

#define W 240
#define H 280

static uint16_t frame[W * H];

static void render(const face_frame_t *f, bool swap)
{
    for (int y = 0; y < H; y += 40) {
        int rows = H - y < 40 ? H - y : 40;
        face_render_band(f, frame + y * W, W, H, y, rows, swap);
    }
}

static int lit(void)
{
    int n = 0;
    for (int i = 0; i < W * H; i++) n += frame[i] != 0;
    return n;
}

static face_frame_t still(face_expr_t e)
{
    face_frame_t f = {.p = *face_preset(e)};
    return f;
}

static void every_expression_draws_something(void)
{
    for (int e = 0; e < FACE_COUNT; e++) {
        face_frame_t f = still((face_expr_t)e);
        render(&f, false);
        int n = lit();
        if (n < 300) fprintf(stderr, "%s: only %d px\n", face_expr_name((face_expr_t)e), n);
        CHECK(n >= 300);
        CHECK(n < W * H / 3);
    }
}

static void band_rendering_matches_full_frame(void)
{
    static uint16_t full[W * H];
    face_frame_t f = still(FACE_LAUGH);
    f.gaze_x = 0.3f;
    face_render_band(&f, full, W, H, 0, H, false);
    for (int y = 0; y < H; y += 7) { /* odd band height crosses shapes */
        int rows = H - y < 7 ? H - y : 7;
        face_render_band(&f, frame + y * W, W, H, y, rows, false);
    }
    CHECK(memcmp(full, frame, sizeof(full)) == 0);
}

static void blink_closes_eyes(void)
{
    face_frame_t f = still(FACE_NEUTRAL);
    render(&f, false);
    int open = lit();
    f.blink = 1.0f;
    render(&f, false);
    int closed = lit();
    CHECK(closed * 4 < open);
}

static void symmetric_when_centred(void)
{
    face_frame_t f = still(FACE_SAD); /* tilt must mirror between eyes */
    render(&f, false);
    int mismatches = 0;
    for (int y = 0; y < H; y++)
        for (int x = 0; x < W / 2; x++)
            mismatches += (frame[y * W + x] != 0) != (frame[y * W + (W - 1 - x)] != 0);
    CHECK(mismatches < 40);
}

static void sad_lowers_inner_corner(void)
{
    face_frame_t f = still(FACE_SAD);
    render(&f, false);
    /* Left eye: inner (right) edge column should start lower than outer edge. */
    float cx = W * 0.5f - 0.5f * f.p.spacing * W;
    int outer_x = (int)(cx - f.p.eye_w * W * 0.3f), inner_x = (int)(cx + f.p.eye_w * W * 0.3f);
    int outer_top = -1, inner_top = -1;
    for (int y = 0; y < H && (outer_top < 0 || inner_top < 0); y++) {
        if (outer_top < 0 && frame[y * W + outer_x]) outer_top = y;
        if (inner_top < 0 && frame[y * W + inner_x]) inner_top = y;
    }
    CHECK(outer_top >= 0 && inner_top > outer_top + 5);
}

static void swap_bytes(void)
{
    face_frame_t f = still(FACE_NEUTRAL);
    render(&f, false);
    uint16_t c = 0;
    for (int i = 0; i < W * H && !c; i++) c = frame[i];
    render(&f, true);
    uint16_t s = 0;
    for (int i = 0; i < W * H && !s; i++) s = frame[i];
    CHECK_EQ_INT(s, (uint16_t)((c >> 8) | (c << 8)));
}

static void animator_eases_and_blinks(void)
{
    face_anim_t a;
    face_anim_init(&a, FACE_NEUTRAL, 42);
    face_frame_t f;
    face_anim_set(&a, FACE_SAD);
    face_anim_step(&a, 0, &f);
    face_anim_step(&a, 60, &f);
    float mid = f.p.tilt;
    CHECK(mid > 0.0f && mid < face_preset(FACE_SAD)->tilt);
    for (uint32_t t = 60; t < 2000; t += 33) face_anim_step(&a, t, &f);
    CHECK(f.p.tilt > face_preset(FACE_SAD)->tilt * 0.98f);

    int blinks = 0;
    float prev = 0;
    for (uint32_t t = 2000; t < 32000; t += 20) {
        face_anim_step(&a, t, &f);
        if (f.blink > 0.5f && prev <= 0.5f) blinks++;
        prev = f.blink;
    }
    CHECK(blinks >= 4 && blinks <= 16);

    face_anim_set(&a, FACE_SLEEPY); /* no blinking while asleep */
    for (uint32_t t = 32000; t < 50000; t += 20) {
        face_anim_step(&a, t, &f);
        CHECK(f.blink == 0.0f);
    }
}

static void animator_is_deterministic(void)
{
    face_anim_t a, b;
    face_frame_t fa, fb;
    face_anim_init(&a, FACE_NEUTRAL, 7);
    face_anim_init(&b, FACE_NEUTRAL, 7);
    for (uint32_t t = 0; t < 10000; t += 33) {
        face_anim_step(&a, t, &fa);
        face_anim_step(&b, t, &fb);
    }
    CHECK(memcmp(&fa, &fb, sizeof(fa)) == 0);
}

int main(void)
{
    RUN(every_expression_draws_something);
    RUN(band_rendering_matches_full_frame);
    RUN(blink_closes_eyes);
    RUN(symmetric_when_centred);
    RUN(sad_lowers_inner_corner);
    RUN(swap_bytes);
    RUN(animator_eases_and_blinks);
    RUN(animator_is_deterministic);
    TEST_EXIT();
}
