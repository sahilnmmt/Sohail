#include "sohail/gfx.h"
#include "test.h"

static void wrap_breaks_on_words(void)
{
    char lines[4][11];
    int n = gfx_wrap("the quick brown fox jumps", 10, &lines[0][0], 4);
    CHECK_EQ_INT(n, 3);
    CHECK_STR(lines[0], "the quick");
    CHECK_STR(lines[1], "brown fox");
    CHECK_STR(lines[2], "jumps");
}

static void wrap_handles_long_words_and_newlines(void)
{
    char lines[4][9];
    int n = gfx_wrap("abcdefghijkl\nhi", 8, &lines[0][0], 4);
    CHECK_EQ_INT(n, 3);
    CHECK_STR(lines[0], "abcdefgh");
    CHECK_STR(lines[1], "ijkl");
    CHECK_STR(lines[2], "hi");
}

static void wrap_truncates(void)
{
    char lines[2][9];
    int n = gfx_wrap("one two three four five six", 8, &lines[0][0], 2);
    CHECK_EQ_INT(n, 2);
    CHECK_STR(lines[0], "one two");
    CHECK_STR(lines[1], "three..");
    CHECK_EQ_INT(gfx_wrap("   ", 8, &lines[0][0], 2), 0);
}

static void text_is_clipped_to_band(void)
{
    uint16_t band[20 * 4] = {0};
    gfx_band_t b = {.buf = band, .width = 20, .y0 = 10, .rows = 4};
    /* Glyph spans rows 8..14; only rows 10..13 land in the band. */
    int x = gfx_text(&b, -2, 8, 1, 0xFFFF, "HI");
    CHECK_EQ_INT(x, -2 + 2 * GFX_FONT_ADVANCE);
    int lit = 0;
    for (int i = 0; i < 80; i++) lit += band[i] != 0;
    CHECK(lit > 0);
    gfx_fill_rect(&b, 15, 0, 100, 100, 0x1234); /* clipped, no overflow */
    CHECK_EQ_INT(band[19], 0x1234);
    CHECK_EQ_INT(gfx_text_width("abc", 2), (3 * 6 - 1) * 2);
}

static void utf8_draws_one_placeholder_per_char(void)
{
    uint16_t a[60 * 7] = {0}, b[60 * 7] = {0};
    gfx_band_t ba = {.buf = a, .width = 60, .y0 = 0, .rows = 7};
    gfx_band_t bb = {.buf = b, .width = 60, .y0 = 0, .rows = 7};
    int xa = gfx_text(&ba, 0, 0, 1, 0xFFFF, "H\xc3\xa9!"); /* "Hé!" */
    int xb = gfx_text(&bb, 0, 0, 1, 0xFFFF, "H?!");
    CHECK_EQ_INT(xa, xb);
    CHECK(memcmp(a, b, sizeof(a)) == 0);
    CHECK_EQ_INT(gfx_text_width("H\xc3\xa9!", 1), gfx_text_width("H?!", 1));
}

static void font_has_expected_glyphs(void)
{
    /* 'A' and 'a' differ, space is blank, '|' is a single centre column. */
    CHECK(memcmp(gfx_font5x7['A' - 0x20], gfx_font5x7['a' - 0x20], 5) != 0);
    for (int i = 0; i < 5; i++) CHECK_EQ_INT(gfx_font5x7[0][i], 0);
    CHECK_EQ_INT(gfx_font5x7['|' - 0x20][2], 0x7F);
    for (int c = 1; c < 95; c++) {
        int any = 0;
        for (int i = 0; i < 5; i++) any |= gfx_font5x7[c][i];
        if (!any) fprintf(stderr, "glyph 0x%02x is empty\n", c + 0x20);
        CHECK(any);
        for (int i = 0; i < 5; i++) CHECK((gfx_font5x7[c][i] & 0x80) == 0); /* 7 rows only */
    }
}

int main(void)
{
    RUN(wrap_breaks_on_words);
    RUN(wrap_handles_long_words_and_newlines);
    RUN(wrap_truncates);
    RUN(text_is_clipped_to_band);
    RUN(utf8_draws_one_placeholder_per_char);
    RUN(font_has_expected_glyphs);
    TEST_EXIT();
}
