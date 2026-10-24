#include "sohail/screen.h"
#include "sohail/gfx.h"
#include "test.h"

#define W 240
#define H 280

static uint16_t fb[W * H];

static robot_view_t body_view(const char *body)
{
    robot_view_t v = {.face = FACE_NEUTRAL};
    snprintf(v.body, sizeof(v.body), "%s", body);
    return v;
}

static void wraps_every_line(void)
{
    static screen_t s;
    screen_init(&s, W, H, 1);
    CHECK_EQ_INT(s.body_chars, 18);
    robot_view_t v = body_view("Dinner is ready! Come down in 5 minutes please");
    screen_begin_frame(&s, &v, 0);
    CHECK_EQ_INT(s.line_count, 3);
    CHECK_STR(s.lines[0], "Dinner is ready!");
    CHECK_STR(s.lines[1], "Come down in 5");
    CHECK_STR(s.lines[2], "minutes please");

    v = body_view("From Grandma - tap to see");
    screen_begin_frame(&s, &v, 40);
    CHECK_EQ_INT(s.line_count, 2);
    CHECK_STR(s.lines[1], "to see");
}

static void narrow_and_wide_screens(void)
{
    static screen_t s;
    screen_init(&s, 128, 128, 1);
    robot_view_t v = body_view("one two three four five six seven");
    screen_begin_frame(&s, &v, 0);
    CHECK_EQ_INT(s.body_chars, 9);
    CHECK_STR(s.lines[0], "one two");
    CHECK_STR(s.lines[1], "three");

    screen_init(&s, 800, 480, 1); /* capped at SCREEN_BODY_CHARS_MAX */
    CHECK_EQ_INT(s.body_chars, SCREEN_BODY_CHARS_MAX);
}

static int lit_rows(int y0, int y1)
{
    int n = 0;
    for (int y = y0; y < y1; y++) {
        for (int x = 0; x < W; x++) {
            if (fb[y * W + x]) { n++; break; }
        }
    }
    return n;
}

static void draws_body_lines_and_code(void)
{
    static screen_t s;
    screen_init(&s, W, H, 1);
    robot_view_t v = body_view("first line here second line here");
    screen_begin_frame(&s, &v, 0);
    screen_render_band(&s, fb, 0, H, false);
    int line_h = GFX_FONT_H * SCREEN_BODY_SCALE + 4, y = (int)(H * 0.70f);
    CHECK(lit_rows(y, y + line_h) >= 10);              /* line 1 */
    CHECK(lit_rows(y + line_h, y + 2 * line_h) >= 10); /* line 2 */

    v = (robot_view_t){.face = FACE_NEUTRAL, .show_code = true, .code = "123456"};
    screen_begin_frame(&s, &v, 40);
    screen_render_band(&s, fb, 0, H, false);
    CHECK(lit_rows(y, y + GFX_FONT_H * 5) >= 30); /* big code digits */

    /* Status dot colour follows connectivity. */
    v.cloud_up = true;
    screen_begin_frame(&s, &v, 80);
    screen_render_band(&s, fb, 0, H, false);
    CHECK_EQ_INT(fb[20 * W + (W - 14)], 0x07E0);
}

int main(void)
{
    RUN(wraps_every_line);
    RUN(narrow_and_wide_screens);
    RUN(draws_body_lines_and_code);
    TEST_EXIT();
}
