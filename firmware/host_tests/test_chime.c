#include "sohail/chime.h"
#include "test.h"

static void lengths_and_chunking(void)
{
    const uint32_t sr = 16000;
    for (int c = 0; c < CHIME_COUNT; c++) {
        size_t len = chime_length((chime_t)c, sr);
        CHECK(len > sr / 20 && len < sr);
        int16_t whole[16000], chunked[16000];
        CHECK_EQ_INT(chime_render((chime_t)c, sr, 80, 0, whole, len + 100), len);
        size_t pos = 0;
        while (pos < len) {
            size_t n = chime_render((chime_t)c, sr, 80, pos, chunked + pos, 256);
            CHECK(n > 0);
            pos += n;
        }
        CHECK(memcmp(whole, chunked, len * sizeof(int16_t)) == 0);
        int peak = 0;
        for (size_t i = 0; i < len; i++) peak = abs(whole[i]) > peak ? abs(whole[i]) : peak;
        CHECK(peak > 3000 && peak <= 32767);
        CHECK(abs(whole[0]) < 200); /* soft attack, no click */
    }
}

static void volume_and_bounds(void)
{
    int16_t buf[64];
    CHECK_EQ_INT(chime_render(CHIME_COUNT, 16000, 50, 0, buf, 64), 0);
    CHECK_EQ_INT(chime_length(CHIME_COUNT, 16000), 0);
    CHECK_EQ_INT(chime_render(CHIME_SENT, 16000, 0, 100, buf, 64), 64);
    for (int i = 0; i < 64; i++) CHECK_EQ_INT(buf[i], 0);
    size_t len = chime_length(CHIME_SENT, 16000);
    CHECK_EQ_INT(chime_render(CHIME_SENT, 16000, 50, len, buf, 64), 0);
}

int main(void)
{
    RUN(lengths_and_chunking);
    RUN(volume_and_bounds);
    TEST_EXIT();
}
